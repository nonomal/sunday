import Foundation
import CoreLocation
import Combine
import UserNotifications

struct OpenMeteoResponse: Codable {
    let daily: DailyData
    let hourly: HourlyData?
    
    struct DailyData: Codable {
        let time: [String]
        let uvIndexMax: [Double]
        let uvIndexClearSkyMax: [Double]?
        let sunrise: [String]
        let sunset: [String]
        
        enum CodingKeys: String, CodingKey {
            case time
            case uvIndexMax = "uv_index_max"
            case uvIndexClearSkyMax = "uv_index_clear_sky_max"
            case sunrise
            case sunset
        }
    }
    
    struct HourlyData: Codable {
        let time: [String]
        let uvIndex: [Double]
        let cloudCover: [Double]?
        
        enum CodingKeys: String, CodingKey {
            case time
            case uvIndex = "uv_index"
            case cloudCover = "cloud_cover"
        }
    }
}

class UVService: ObservableObject {
    @Published var currentUV: Double = 0.0
    @Published var maxUV: Double = 0.0
    @Published var tomorrowMaxUV: Double = 0.0
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var safeExposureMinutes: [Int: Int] = [:]
    @Published var todaySunrise: Date?
    @Published var todaySunset: Date?
    @Published var tomorrowSunrise: Date?
    @Published var tomorrowSunset: Date?
    @Published var currentAltitude: Double = 0.0
    @Published var uvMultiplier: Double = 1.0
    @Published var currentCloudCover: Double = 0.0
    @Published var currentMoonPhase: Double = 0.0
    @Published var currentMoonPhaseName: String = ""
    private var lastMoonPhaseUpdate: Date?
    
    var shouldShowTomorrowTimes: Bool {
        guard let todaySunset = todaySunset else { return false }
        let now = Date()
        let calendar = Calendar.current
        // Show tomorrow's times if we're past sunset but not yet midnight
        return now > todaySunset && calendar.isDateInToday(now)
    }
    
    var displaySunrise: Date? {
        shouldShowTomorrowTimes ? tomorrowSunrise : todaySunrise
    }
    
    var displaySunset: Date? {
        shouldShowTomorrowTimes ? tomorrowSunset : todaySunset
    }
    
    var displayMaxUV: Double {
        shouldShowTomorrowTimes ? tomorrowMaxUV : maxUV
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var notificationScheduled = false
    
    func fetchUVData(for location: CLLocation) {
        isLoading = true
        lastError = nil
        
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        let altitude = location.altitude // Get altitude from location
        
        // Get current time components for UV interpolation
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        
        // Open-Meteo API - completely free, no API key needed!
        // Include elevation for more accurate UV calculations
        // Get 2 days of data to have tomorrow's sunrise/sunset
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&elevation=\(altitude)&daily=uv_index_max,uv_index_clear_sky_max,sunrise,sunset&hourly=uv_index,cloud_cover&timezone=auto&forecast_days=2"
        
        guard let url = URL(string: urlString) else {
            lastError = "Invalid URL"
            isLoading = false
            return
        }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: OpenMeteoResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.lastError = error.localizedDescription
                        self?.mockUVData(for: location)
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }
                    
                    
                    // Calculate altitude adjustment (UV increases ~10% per 1000m)
                    // Note: location.altitude can be negative (below sea level) or -1 if unknown
                    let validAltitude = location.altitude >= 0 ? location.altitude : 0
                    self.currentAltitude = validAltitude
                    let altitudeKm = validAltitude / 1000.0
                    let altitudeMultiplier = 1.0 + (altitudeKm * 0.1)
                    self.uvMultiplier = altitudeMultiplier
                    
                    // Get today's data (first item in arrays)
                    if let todayMaxUV = response.daily.uvIndexMax.first {
                        self.maxUV = todayMaxUV * altitudeMultiplier
                    }
                    
                    // Get tomorrow's max UV
                    if response.daily.uvIndexMax.count > 1 {
                        self.tomorrowMaxUV = response.daily.uvIndexMax[1] * altitudeMultiplier
                    }
                    
                    // Parse sunrise and sunset times for today and tomorrow
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
                    formatter.timeZone = TimeZone.current // Use local timezone
                    
                    // Today's times
                    if response.daily.sunrise.count > 0,
                       response.daily.sunset.count > 0 {
                        self.todaySunrise = formatter.date(from: response.daily.sunrise[0])
                        self.todaySunset = formatter.date(from: response.daily.sunset[0])
                        
                        // Tomorrow's times
                        if response.daily.sunrise.count > 1,
                           response.daily.sunset.count > 1 {
                            self.tomorrowSunrise = formatter.date(from: response.daily.sunrise[1])
                            self.tomorrowSunset = formatter.date(from: response.daily.sunset[1])
                            
                        }
                        
                        // Schedule notifications
                        self.scheduleSunNotifications()
                    }
                    
                    // Fetch moon phase if not updated recently (update every 6 hours)
                    if self.lastMoonPhaseUpdate == nil || 
                       Date().timeIntervalSince(self.lastMoonPhaseUpdate!) > 21600 {
                        self.fetchMoonPhase(for: location)
                    }
                    
                    // Get current hour's UV index with interpolation
                    if let hourlyUV = response.hourly?.uvIndex,
                       hour < hourlyUV.count {
                        let currentHourUV = hourlyUV[hour]
                        
                        // Calculate interpolation factor (0.0 to 1.0 based on minutes)
                        let interpolationFactor = Double(minute) / 60.0
                        
                        // Get next hour's UV for interpolation
                        var interpolatedUV = currentHourUV
                        if hour + 1 < hourlyUV.count {
                            let nextHourUV = hourlyUV[hour + 1]
                            // Linear interpolation between current and next hour
                            interpolatedUV = currentHourUV + (nextHourUV - currentHourUV) * interpolationFactor
                        }
                        
                        self.currentUV = interpolatedUV * altitudeMultiplier
                    } else {
                        // Fallback: estimate current UV based on max and time of day
                        self.currentUV = self.estimateCurrentUV(maxUV: self.maxUV, hour: hour)
                    }
                    
                    // Get current hour's cloud cover
                    if let cloudCover = response.hourly?.cloudCover,
                       hour < cloudCover.count {
                        self.currentCloudCover = cloudCover[hour]
                    }
                    
                    
                    // Calculate safe exposure times
                    self.calculateSafeExposureTimes()
                }
            )
            .store(in: &cancellables)
    }
    
    private func mockUVData(for location: CLLocation) {
        let hour = Calendar.current.component(.hour, from: Date())
        let latitude = abs(location.coordinate.latitude)
        
        // Handle altitude for mock data
        let validAltitude = location.altitude >= 0 ? location.altitude : 0
        currentAltitude = validAltitude
        let altitudeKm = validAltitude / 1000.0
        let altitudeMultiplier = 1.0 + (altitudeKm * 0.1)
        uvMultiplier = altitudeMultiplier
        
        let basePeak = latitude < 23.5 ? 11.0 : latitude < 45 ? 8.0 : 6.0
        maxUV = basePeak * altitudeMultiplier
        currentUV = estimateCurrentUV(maxUV: maxUV, hour: hour)
        
        // Mock sunrise/sunset times based on latitude
        let calendar = Calendar.current
        var sunriseComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        var sunsetComponents = sunriseComponents
        
        // Simplified sunrise/sunset calculation
        sunriseComponents.hour = latitude < 45 ? 6 : 7
        sunsetComponents.hour = latitude < 45 ? 19 : 18
        
        todaySunrise = calendar.date(from: sunriseComponents)
        todaySunset = calendar.date(from: sunsetComponents)
        
        calculateSafeExposureTimes()
        scheduleSunNotifications()
    }
    
    private func estimateCurrentUV(maxUV: Double, hour: Int) -> Double {
        // UV follows a bell curve peaking around 1 PM
        let peakHour = 13.0
        let dayStart = 6.0
        let dayEnd = 19.0
        
        if Double(hour) < dayStart || Double(hour) > dayEnd {
            return 0.0
        }
        
        let hourFactor = 1.0 - (abs(Double(hour) - peakHour) / peakHour)
        return max(0, maxUV * hourFactor * 0.9)
    }
    
    private func calculateSafeExposureTimes() {
        let baseExposure = 120.0
        let uvToUse = max(currentUV, 0.1)
        
        safeExposureMinutes = [
            1: Int(baseExposure / uvToUse * 6),
            2: Int(baseExposure / uvToUse * 5),
            3: Int(baseExposure / uvToUse * 4),
            4: Int(baseExposure / uvToUse * 3),
            5: Int(baseExposure / uvToUse * 2),
            6: Int(baseExposure / uvToUse)
        ]
    }
    
    private func scheduleSunNotifications() {
        // Check if we already scheduled for today
        let calendar = Calendar.current
        let lastScheduledKey = "lastNotificationScheduledDate"
        let lastScheduledDate = UserDefaults.standard.object(forKey: lastScheduledKey) as? Date
        let isToday = lastScheduledDate.map { calendar.isDateInToday($0) } ?? false
        
        guard !isToday else { return }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            
            // Remove old notifications
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["sunrise", "sunset", "safeTimeReached"])
            
            DispatchQueue.main.async {
                self.scheduleNotification(
                    at: self.todaySunrise,
                    title: "☀️ The sun is up!",
                    body: "Today's max UV index: \(Int(self.maxUV)). Start tracking your vitamin D!",
                    identifier: "sunrise"
                )
                
                self.scheduleNotification(
                    at: self.todaySunset,
                    title: "🌅 The sun is setting.",
                    body: "Check your vitamin D progress in Sunday.",
                    identifier: "sunset"
                )
                
                UserDefaults.standard.set(Date(), forKey: lastScheduledKey)
                self.notificationScheduled = true
            }
        }
    }
    
    private func scheduleNotification(at date: Date?, title: String, body: String, identifier: String) {
        guard let date = date else { return }
        
        // Only schedule if the date is in the future
        if date <= Date() {
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Use time interval trigger for more reliable delivery
        let timeInterval = date.timeIntervalSinceNow
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleSafeTimeNotification(for skinType: SkinType) {
        guard let safeMinutes = safeExposureMinutes[skinType.rawValue] else { return }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            
            // Cancel existing safe time notification
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["safeTimeReached"])
            
            _ = Date().addingTimeInterval(TimeInterval(safeMinutes * 60))
            
            let content = UNMutableNotificationContent()
            content.title = "⚠️ Safe exposure time reached!"
            content.body = "You've reached your safe sun exposure limit (\(safeMinutes) minutes). Consider seeking shade."
            content.sound = .default
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(safeMinutes * 60), repeats: false)
            let request = UNNotificationRequest(identifier: "safeTimeReached", content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    func cancelSafeTimeNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["safeTimeReached"])
    }
    
    private func fetchMoonPhase(for location: CLLocation) {
        // Use Farmsense API - completely free, no API key needed!
        // API expects unix timestamp (uses first 10 digits)
        let timestamp = Int(Date().timeIntervalSince1970)
        let urlString = "https://api.farmsense.net/v1/moonphases/?d=\(timestamp)"
        
        
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if error != nil { return }
            
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let moonData = json.first {
                    
                    // Get illumination percentage (comes as 0-1 decimal)
                    let illuminationValue = moonData["Illumination"] as? Double ?? 0.0
                    
                    DispatchQueue.main.async {
                        // Simply use illumination value directly (0-1 scale)
                        self.currentMoonPhase = illuminationValue
                        
                        // Store phase name
                        if let phaseName = moonData["Phase"] as? String {
                            self.currentMoonPhaseName = phaseName
                        }
                        
                        // Update last fetch time
                        self.lastMoonPhaseUpdate = Date()
                        
                    }
                }
            } catch {
                // Silent error handling
            }
        }.resume()
    }
}
