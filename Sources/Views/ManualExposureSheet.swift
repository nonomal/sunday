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
    @State private var selectedSunscreen: SunscreenLevel = .none
    @State private var showClothingPicker = false
    @State private var showSunscreenPicker = false
    @State private var isCalculating = false
    @State private var calculatedVitaminD: Double = 0
    @State private var errorMessage: String?
    @State private var uvDataPoints: [(time: Date, uv: Double)] = []
    
    private let calendar = Calendar.current
    
    // Time range limits - only allow today's past times
    private var timeRange: ClosedRange<Date> {
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        return startOfDay...now
    }
    
    private var formattedDuration: String {
        guard endTime > startTime else { return "--" }
        let minutes = Int(endTime.timeIntervalSince(startTime) / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "\(hours) hr" : "\(hours) hr \(remaining) min"
    }

    private var formattedAmount: String {
        if calculatedVitaminD <= 0 { return "--" }
        if calculatedVitaminD < 1000 { return "\(Int(calculatedVitaminD)) IU" }
        if calculatedVitaminD < 100000 {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
            return "\(f.string(from: NSNumber(value: calculatedVitaminD)) ?? "\(Int(calculatedVitaminD))") IU"
        }
        return String(format: "%.0fK IU", calculatedVitaminD / 1000)
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Gradient background to match SessionCompletionSheet
                LinearGradient(
                    colors: [Color(hex: "4a90e2"), Color(hex: "7bb7e5")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                    // Header icon
                    VStack(spacing: 20) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.yellow)
                            .symbolEffect(.pulse)
                            .padding(.top, 10)
                    }
                    
                    // Time selection
                    VStack(spacing: 16) {
                        // Start time
                        VStack(alignment: .leading, spacing: 8) {
                            Text("START TIME")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .tracking(1.2)
                            
                            DatePicker("", selection: $startTime, in: timeRange, displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .onChange(of: startTime) { _, newValue in
                                    // Ensure end time is after start time
                                    if endTime <= newValue {
                                        endTime = min(newValue.addingTimeInterval(300), Date()) // Add 5 minutes
                                    }
                                    // Recalculate vitamin D
                                    calculateVitaminD()
                                }
                        }
                        
                        // End time
                        VStack(alignment: .leading, spacing: 8) {
                            Text("END TIME")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .tracking(1.2)
                            
                            DatePicker("", selection: $endTime, in: startTime...Date(), displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .onChange(of: endTime) { _, _ in
                                    // Recalculate vitamin D
                                    calculateVitaminD()
                                }
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(12)
                    
                    // Duration displayed in header above
                    
                    // Clothing and Sunscreen selection
                    HStack(spacing: 12) {
                        // Clothing button
                        Button(action: { showClothingPicker.toggle() }) {
                            VStack(spacing: 10) {
                                Text("CLOTHING")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                                    .tracking(1.5)
                                
                                HStack {
                                    Text(selectedClothing.shortDescription)
                                        .font(.system(size: 16, weight: .medium))
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(15)
                        }
                        .sheet(isPresented: $showClothingPicker) {
                            ClothingPicker(selection: $selectedClothing)
                                .presentationDetents([.medium])
                                .presentationDragIndicator(.visible)
                        }
                        .onChange(of: selectedClothing) { _, _ in
                            calculateVitaminD()
                        }
                        
                        // Sunscreen button
                        Button(action: { showSunscreenPicker.toggle() }) {
                            VStack(spacing: 10) {
                                Text("SUNSCREEN")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                                    .tracking(1.5)
                                
                                HStack {
                                    Text(selectedSunscreen.description)
                                        .font(.system(size: 16, weight: .medium))
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(15)
                        }
                        .sheet(isPresented: $showSunscreenPicker) {
                            SunscreenPicker(selection: $selectedSunscreen)
                                .presentationDetents([.medium])
                                .presentationDragIndicator(.visible)
                        }
                        .onChange(of: selectedSunscreen) { _, _ in
                            calculateVitaminD()
                        }
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Result display
                    if isCalculating {
                        ProgressView("Calculating...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding()
                            .frame(maxWidth: .infinity)
                    } else if calculatedVitaminD > 0 {
                        VStack(spacing: 16) {
                            Text("UV DURING EXPOSURE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .tracking(1.2)
                            
                            // UV data points used
                            if !uvDataPoints.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(uvDataPoints, id: \.time) { point in
                                        HStack {
                                            Text(point.time, style: .time)
                                                .font(.caption2)
                                                .foregroundColor(.white.opacity(0.8))
                                            Spacer()
                                            Text("UV: \(String(format: "%.1f", point.uv))")
                                                .font(.caption2)
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(12)

                        // Summary + Save card
                        VStack(spacing: 12) {
                            // Summary just above the Save button (no surrounding box)
                            VStack(spacing: 6) {
                                Text("VITAMIN D ESTIMATE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .tracking(1.2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .allowsTightening(true)
                                Text(formattedAmount)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .allowsTightening(true)
                            }
                            .frame(maxWidth: .infinity)

                            // Save button
                            Button(action: saveToHealth) {
                                HStack {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 16))
                                    Text("Save to Health")
                                        .font(.system(size: 18, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(15)
                            }
                            .disabled(isCalculating || calculatedVitaminD <= 0)
                        }
                        .padding()
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(12)
                    }
                    // Close button
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
            }
            }
            .navigationTitle("Log Past Exposure")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .onAppear {
            // Set default times - 1 hour ago to now
            let now = Date()
            startTime = now.addingTimeInterval(-3600) // 1 hour ago
            endTime = now
            
            // Calculate initial vitamin D
            calculateVitaminD()
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
                        clothingLevel: selectedClothing,
                        sunscreenLevel: selectedSunscreen
                    )
                    
                    totalVitaminD += vitaminD
                }
                
                calculatedVitaminD = totalVitaminD
                isCalculating = false
            }
        }
    }
    
    private func fetchHistoricalUV(for location: CLLocation, from startTime: Date, to endTime: Date) async -> [(time: Date, uv: Double)] {
        // Prefer cached hourly UV from UVService when available
        let cached = uvService.historicalUVPoints(from: startTime, to: endTime, near: location)
        if !cached.isEmpty {
            return cached.map { (time: $0.0, uv: $0.1) }
        }

        // Fallback: estimate via solar elevation if cache is unavailable
        var dataPoints: [(time: Date, uv: Double)] = []
        var currentTime = startTime
        let hourInterval: TimeInterval = 3600 // 1 hour
        while currentTime <= endTime {
            let uvIndex = await estimateUVForTime(currentTime, at: location)
            dataPoints.append((time: currentTime, uv: uvIndex))
            currentTime = currentTime.addingTimeInterval(hourInterval)
        }
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
