import SwiftUI
import CoreLocation

struct ManualExposureSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var vitaminDCalculator: VitaminDCalculator
    @EnvironmentObject var uvService: UVService
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var healthManager: HealthManager
    
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var selectedClothing: ClothingLevel = .light
    @State private var isCalculating = false
    @State private var calculatedVitaminD: Double = 0
    @State private var showResult = false
    @State private var errorMessage: String?
    @State private var uvDataPoints: [(time: Date, uv: Double)] = []
    
    private let calendar = Calendar.current
    
    // Time range limits - only allow today's past times
    private var timeRange: ClosedRange<Date> {
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        return startOfDay...now
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Instructions
                    Text("Log past sun exposure from today")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.top)
                    
                    // Time selection
                    VStack(spacing: 16) {
                        // Start time
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Start Time")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            DatePicker("", selection: $startTime, in: timeRange, displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .onChange(of: startTime) { _, newValue in
                                    // Ensure end time is after start time
                                    if endTime <= newValue {
                                        endTime = min(newValue.addingTimeInterval(300), Date()) // Add 5 minutes
                                    }
                                }
                        }
                        
                        Divider()
                        
                        // End time
                        VStack(alignment: .leading, spacing: 8) {
                            Text("End Time")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            DatePicker("", selection: $endTime, in: startTime...Date(), displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Duration display
                    if endTime > startTime {
                        let duration = endTime.timeIntervalSince(startTime)
                        let minutes = Int(duration / 60)
                        Text("Duration: \(minutes) minutes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Clothing selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What were you wearing?")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        ForEach(ClothingLevel.allCases, id: \.self) { level in
                            Button(action: { selectedClothing = level }) {
                                HStack {
                                    Image(systemName: level.iconName)
                                        .font(.system(size: 24))
                                        .frame(width: 30)
                                    
                                    Text(level.name)
                                        .font(.system(size: 16))
                                    
                                    Spacer()
                                    
                                    if selectedClothing == level {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding()
                                .background(selectedClothing == level ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Calculate button
                    Button(action: calculateVitaminD) {
                        if isCalculating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Calculate Vitamin D")
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                    .disabled(isCalculating || endTime <= startTime)
                    
                    // Result display
                    if showResult {
                        VStack(spacing: 16) {
                            Text("Estimated Vitamin D")
                                .font(.headline)
                            
                            Text("\(Int(calculatedVitaminD)) IU")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.orange)
                            
                            // UV data points used
                            if !uvDataPoints.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("UV Index during exposure:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    ForEach(uvDataPoints, id: \.time) { point in
                                        HStack {
                                            Text(point.time, style: .time)
                                                .font(.caption2)
                                            Spacer()
                                            Text("UV: \(String(format: "%.1f", point.uv))")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                            
                            // Save button
                            Button(action: saveToHealth) {
                                Text("Save to Health")
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .cornerRadius(12)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Log Past Exposure")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() },
                trailing: Button("Done") { dismiss() }
                    .opacity(showResult ? 1 : 0)
            )
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Set default times - 1 hour ago to now
            let now = Date()
            startTime = now.addingTimeInterval(-3600) // 1 hour ago
            endTime = now
        }
    }
    
    private func calculateVitaminD() {
        errorMessage = nil
        isCalculating = true
        uvDataPoints.removeAll()
        
        // Ensure we have location
        guard let location = locationManager.location else {
            errorMessage = "Location not available"
            isCalculating = false
            return
        }
        
        Task {
            // Fetch historical UV data for today
            let historicalUV = await fetchHistoricalUV(for: location, from: startTime, to: endTime)
            
            await MainActor.run {
                guard !historicalUV.isEmpty else {
                    errorMessage = "Could not fetch UV data for this time period"
                    isCalculating = false
                    return
                }
                
                // Store UV data points for display
                uvDataPoints = historicalUV
                
                // Calculate vitamin D for each interval
                var totalVitaminD = 0.0
                
                for i in 0..<historicalUV.count {
                    let uvIndex = historicalUV[i].uv
                    
                    // Calculate duration for this interval
                    let intervalStart = historicalUV[i].time
                    let intervalEnd: Date
                    
                    if i < historicalUV.count - 1 {
                        intervalEnd = historicalUV[i + 1].time
                    } else {
                        intervalEnd = endTime
                    }
                    
                    let duration = intervalEnd.timeIntervalSince(intervalStart) / 60.0 // minutes
                    
                    // Calculate vitamin D for this interval
                    let vitaminD = vitaminDCalculator.calculateVitaminD(
                        uvIndex: uvIndex,
                        exposureMinutes: duration,
                        skinType: vitaminDCalculator.skinType,
                        clothingLevel: selectedClothing
                    )
                    
                    totalVitaminD += vitaminD
                }
                
                calculatedVitaminD = totalVitaminD
                showResult = true
                isCalculating = false
            }
        }
    }
    
    private func fetchHistoricalUV(for location: CLLocation, from startTime: Date, to endTime: Date) async -> [(time: Date, uv: Double)] {
        // For now, we'll use the current UV data and interpolate
        // In a real implementation, this would fetch hourly UV data for today
        
        var dataPoints: [(time: Date, uv: Double)] = []
        
        // Get hourly intervals
        var currentTime = startTime
        let hourInterval: TimeInterval = 3600 // 1 hour
        
        while currentTime <= endTime {
            // For each hour, try to get UV data
            // This is a simplified version - in reality, you'd call the UV API for historical data
            let uvIndex = await estimateUVForTime(currentTime, at: location)
            dataPoints.append((time: currentTime, uv: uvIndex))
            currentTime = currentTime.addingTimeInterval(hourInterval)
        }
        
        // Add final point if needed
        if dataPoints.last?.time != endTime {
            let uvIndex = await estimateUVForTime(endTime, at: location)
            dataPoints.append((time: endTime, uv: uvIndex))
        }
        
        return dataPoints
    }
    
    private func estimateUVForTime(_ time: Date, at location: CLLocation) async -> Double {
        // This is a simplified estimation based on solar elevation
        // In a real app, you'd fetch actual historical UV data from the API
        
        let solarData = calculateSolarPosition(for: time, at: location)
        
        // Simple UV estimation based on solar elevation
        if solarData.elevation <= 0 {
            return 0 // No UV when sun is below horizon
        }
        
        // Get the current day's max UV (this should come from API)
        let maxUV = await getCurrentDayMaxUV()
        
        // Estimate UV based on solar elevation
        // UV is roughly proportional to sin(elevation) with adjustments
        let elevationRadians = solarData.elevation * .pi / 180
        let uvFactor = max(0, sin(elevationRadians))
        
        return maxUV * uvFactor
    }
    
    private func getCurrentDayMaxUV() async -> Double {
        // In a real implementation, this would fetch from the API
        // For now, use current UV as a rough approximation
        return max(uvService.currentUV, 5.0) // Assume at least UV 5 for midday
    }
    
    private func calculateSolarPosition(for date: Date, at location: CLLocation) -> (elevation: Double, azimuth: Double) {
        // Simplified solar position calculation
        // In production, use a proper astronomy library
        
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        
        // Solar declination (simplified)
        let declination = 23.45 * sin(360.0 * Double(dayOfYear - 81) / 365.0 * .pi / 180.0)
        
        // Hour angle
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hourOfDay = Double(components.hour ?? 12) + Double(components.minute ?? 0) / 60.0
        let solarNoon = 12.0 - longitude / 15.0 // Simplified
        let hourAngle = 15.0 * (hourOfDay - solarNoon)
        
        // Solar elevation (simplified)
        let latRad = latitude * .pi / 180.0
        let decRad = declination * .pi / 180.0
        let hourRad = hourAngle * .pi / 180.0
        
        let elevation = asin(sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(hourRad)) * 180.0 / .pi
        
        return (elevation: elevation, azimuth: 0) // Azimuth calculation omitted for simplicity
    }
    
    private func saveToHealth() {
        // Save to health
        healthManager.saveVitaminD(amount: calculatedVitaminD)
        
        // Update today's total
        vitaminDCalculator.addManualEntry(amount: calculatedVitaminD)
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Dismiss after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
}

// Extension to support ClothingLevel
extension ClothingLevel {
    var iconName: String {
        switch self {
        case .none: return "figure.stand.dress.line.vertical.figure"
        case .minimal: return "sun.max"
        case .light: return "tshirt"
        case .moderate: return "figure.stand"
        case .heavy: return "person.fill"
        }
    }
    
    var name: String {
        switch self {
        case .none: return "Nude"
        case .minimal: return "Minimal (Swimwear)"
        case .light: return "Light (T-shirt & Shorts)"
        case .moderate: return "Moderate (Pants & T-shirt)"
        case .heavy: return "Heavy (Long sleeves & Pants)"
        }
    }
}