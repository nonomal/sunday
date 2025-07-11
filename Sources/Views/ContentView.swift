import SwiftUI
import CoreLocation

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var uvService: UVService
    @EnvironmentObject var vitaminDCalculator: VitaminDCalculator
    @EnvironmentObject var healthManager: HealthManager
    
    @State private var showClothingPicker = false
    @State private var showSkinTypePicker = false
    @State private var todaysTotal: Double = 0
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            VStack(spacing: 20) {
                headerSection
                uvSection
                vitaminDSection
                exposureToggle
                clothingSection
                skinTypeSection
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
        }
        .onAppear {
            setupApp()
        }
        .onReceive(timer) { _ in
            updateData()
            // Reload today's total periodically
            if Int(Date().timeIntervalSince1970) % 60 == 0 {
                loadTodaysTotal()
            }
        }
        .onChange(of: vitaminDCalculator.isInSun) { _ in
            handleSunToggle()
        }
        .onChange(of: locationManager.location) { newLocation in
            if let location = newLocation {
                uvService.fetchUVData(for: location)
            }
        }
        .onChange(of: vitaminDCalculator.clothingLevel) { _ in
            // Update rate when clothing changes
            vitaminDCalculator.updateUV(uvService.currentUV)
        }
        .onChange(of: vitaminDCalculator.skinType) { _ in
            // Update rate when skin type changes
            vitaminDCalculator.updateUV(uvService.currentUV)
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private var gradientColors: [Color] {
        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        let timeProgress = Double(hour) + Double(minute) / 60.0
        
        if timeProgress < 5 || timeProgress > 22 {
            // Night (deep dark blue)
            return [Color(hex: "0f1c3d"), Color(hex: "0a1228")]
        } else if timeProgress < 6 {
            // Pre-dawn (dark blue transitioning)
            return [Color(hex: "1e3a5f"), Color(hex: "2d4a7c")]
        } else if timeProgress < 6.5 {
            // Early dawn (blue to purple)
            return [Color(hex: "3d5a80"), Color(hex: "5c7cae")]
        } else if timeProgress < 7 {
            // Dawn (purple to pink)
            return [Color(hex: "5c7cae"), Color(hex: "ee9b7a")]
        } else if timeProgress < 8 {
            // Sunrise (pink to light blue)
            return [Color(hex: "f4a261"), Color(hex: "87ceeb")]
        } else if timeProgress < 10 {
            // Morning (clear blue sky)
            return [Color(hex: "5ca9d6"), Color(hex: "87ceeb")]
        } else if timeProgress < 16 {
            // Midday (bright blue sky)
            return [Color(hex: "4a90e2"), Color(hex: "7bb7e5")]
        } else if timeProgress < 17 {
            // Late afternoon (slightly warmer blue)
            return [Color(hex: "5ca9d6"), Color(hex: "87b8d4")]
        } else if timeProgress < 18.5 {
            // Golden hour (warm golden)
            return [Color(hex: "f4a261"), Color(hex: "e76f51")]
        } else if timeProgress < 19.5 {
            // Sunset (orange to pink)
            return [Color(hex: "e76f51"), Color(hex: "c44569")]
        } else if timeProgress < 20.5 {
            // Late sunset (pink to purple)
            return [Color(hex: "c44569"), Color(hex: "6a4c93")]
        } else {
            // Dusk (purple to dark blue)
            return [Color(hex: "6a4c93"), Color(hex: "1e3a5f")]
        }
    }
    
    private var headerSection: some View {
        Text("SUNDAY")
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .tracking(2)
    }
    
    private var uvSection: some View {
        VStack(spacing: 15) {
            Text("UV INDEX")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .tracking(1.5)
            
            Text(String(format: "%.1f", uvService.currentUV))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            HStack(spacing: 15) {
                VStack(spacing: 5) {
                    Text("MAX TODAY")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(String(format: "%.1f", uvService.maxUV))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 5) {
                    Text("SAFE TIME")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(safeExposureTime) min")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 5) {
                    Text("SUNRISE")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(formatTime(uvService.todaySunrise))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 5) {
                    Text("SUNSET")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(formatTime(uvService.todaySunset))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            // Show altitude info if significant
            if uvService.currentAltitude > 100 {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(Int(uvService.currentAltitude))m")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text("(+\(Int((uvService.uvMultiplier - 1) * 100))% UV)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, 5)
            }
        }
        .padding(.vertical, 25)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.2))
        .cornerRadius(20)
    }
    
    private var exposureToggle: some View {
        Button(action: {
            vitaminDCalculator.toggleSunExposure(uvIndex: uvService.currentUV)
            
            // Handle safe time notifications
            if vitaminDCalculator.isInSun {
                uvService.scheduleSafeTimeNotification(for: vitaminDCalculator.skinType)
            } else {
                uvService.cancelSafeTimeNotification()
            }
        }) {
            HStack {
                Image(systemName: vitaminDCalculator.isInSun ? "sun.max.fill" : "sun.max")
                    .font(.system(size: 24))
                    .symbolEffect(.pulse, isActive: vitaminDCalculator.isInSun)
                
                Text(vitaminDCalculator.isInSun ? "Stop" : 
                     uvService.currentUV == 0 ? "No UV available" : "Track sun exposure")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(vitaminDCalculator.isInSun ? Color.yellow.opacity(0.3) : Color.black.opacity(0.2))
            .cornerRadius(15)
            .animation(.easeInOut(duration: 0.3), value: vitaminDCalculator.isInSun)
        }
        .disabled(uvService.currentUV == 0 && !vitaminDCalculator.isInSun)
        .opacity(uvService.currentUV == 0 && !vitaminDCalculator.isInSun ? 0.6 : 1.0)
    }
    
    private var clothingSection: some View {
        Button(action: { showClothingPicker.toggle() }) {
            VStack(spacing: 10) {
                Text("CLOTHING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1.5)
                
                HStack {
                    Text(vitaminDCalculator.clothingLevel.description)
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
            ClothingPicker(selection: $vitaminDCalculator.clothingLevel)
        }
    }
    
    private var skinTypeSection: some View {
        Button(action: { showSkinTypePicker.toggle() }) {
            VStack(spacing: 10) {
                Text("SKIN TYPE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1.5)
                
                HStack {
                    Text(vitaminDCalculator.skinType.description)
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
        .sheet(isPresented: $showSkinTypePicker) {
            SkinTypePicker(selection: $vitaminDCalculator.skinType)
        }
    }
    
    private var vitaminDSection: some View {
        VStack(spacing: 15) {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 8) {
                    Text("SESSION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(1.2)
                        .frame(height: 12)
                    
                    HStack(spacing: 4) {
                        Text(formatVitaminDNumber(vitaminDCalculator.sessionVitaminD))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .monospacedDigit()
                            .frame(minWidth: 70, alignment: .trailing)
                        
                        Text("IU")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 20, alignment: .leading)
                    }
                    .frame(height: 34)
                    
                    ZStack {
                        Text("Not tracking")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                            .opacity(vitaminDCalculator.isInSun ? 0 : 1)
                        
                        if vitaminDCalculator.isInSun, let startTime = vitaminDCalculator.sessionStartTime {
                            Text(sessionDurationString(from: startTime))
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .frame(height: 16)
                }
                .frame(minWidth: 100)
                
                VStack(spacing: 8) {
                    ZStack {
                        Text("POTENTIAL")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .tracking(1.2)
                            .opacity(vitaminDCalculator.isInSun ? 0 : 1)
                        
                        Text("RATE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .tracking(1.2)
                            .opacity(vitaminDCalculator.isInSun ? 1 : 0)
                    }
                    .frame(height: 12)
                    
                    Text("\(Int(vitaminDCalculator.currentVitaminDRate))")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .frame(minWidth: 70)
                        .frame(height: 34)
                    
                    Text("IU/hour")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(height: 16)
                }
                .frame(minWidth: 100)
                
                VStack(spacing: 8) {
                    Text("TODAY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(1.2)
                        .frame(height: 12)
                    
                    Text(formatTodaysTotal(todaysTotal))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .frame(minWidth: 70)
                        .frame(height: 34)
                    
                    Text("IU total")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(height: 16)
                }
                .frame(minWidth: 100)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.2))
        .cornerRadius(20)
    }
    
    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    private var safeExposureTime: Int {
        uvService.safeExposureMinutes[vitaminDCalculator.skinType.rawValue] ?? 60
    }
    
    private func setupApp() {
        locationManager.requestPermission()
        healthManager.requestAuthorization()
        loadTodaysTotal()
        
        // Fetch UV data on startup
        if let location = locationManager.location {
            uvService.fetchUVData(for: location)
        }
    }
    
    private func updateData() {
        guard let location = locationManager.location else { return }
        
        if Int(Date().timeIntervalSince1970) % 300 == 0 {
            uvService.fetchUVData(for: location)
        }
        
        vitaminDCalculator.updateUV(uvService.currentUV)
    }
    
    private func handleSunToggle() {
        if !vitaminDCalculator.isInSun && vitaminDCalculator.sessionVitaminD > 0 {
            let sessionAmount = vitaminDCalculator.sessionVitaminD
            healthManager.saveVitaminD(amount: sessionAmount)
            // Add the session amount to today's total immediately
            todaysTotal += sessionAmount
            // Reset the session vitamin D after saving
            vitaminDCalculator.sessionVitaminD = 0.0
            // Then reload from HealthKit to ensure accuracy
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                loadTodaysTotal()
            }
        }
    }
    
    private func loadTodaysTotal() {
        healthManager.getTodaysVitaminD { total in
            todaysTotal = total ?? 0
        }
    }
    
    private func formatVitaminD(_ value: Double) -> String {
        if value < 1 {
            return String(format: "%.2f IU", value)
        } else if value < 10 {
            return String(format: "%.1f IU", value)
        } else {
            return "\(Int(value)) IU"
        }
    }
    
    private func formatVitaminDNumber(_ value: Double) -> String {
        if value < 1 {
            return String(format: "%.2f", value)
        } else if value < 10 {
            return String(format: "%.1f", value)
        } else if value < 100000 {
            return "\(Int(value))"
        } else {
            // Handle very large numbers with K notation
            return String(format: "%.0fK", value / 1000)
        }
    }
    
    private func formatTodaysTotal(_ value: Double) -> String {
        if value < 100000 {
            return "\(Int(value))"
        } else {
            return String(format: "%.0fK", value / 1000)
        }
    }
    
    private func sessionDurationString(from startTime: Date) -> String {
        let duration = Date().timeIntervalSince(startTime)
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return "\(seconds)s"
        }
    }
}

struct ClothingPicker: View {
    @Binding var selection: ClothingLevel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(ClothingLevel.allCases, id: \.self) { level in
                    Button(action: {
                        selection = level
                        dismiss()
                    }) {
                        HStack {
                            Text(level.description)
                                .foregroundColor(.primary)
                            Spacer()
                            if selection == level {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Clothing Level")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}

struct SkinTypePicker: View {
    @Binding var selection: SkinType
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(SkinType.allCases, id: \.self) { type in
                    Button(action: {
                        selection = type
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Type \(type.rawValue)")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(type.description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(skinTypeDetail(for: type))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selection == type {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Skin Type")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
    
    private func skinTypeDetail(for type: SkinType) -> String {
        switch type {
        case .type1: return "Always burns, never tans"
        case .type2: return "Usually burns, tans minimally"
        case .type3: return "Sometimes burns, tans uniformly"
        case .type4: return "Burns minimally, tans well"
        case .type5: return "Rarely burns, tans profusely"
        case .type6: return "Never burns, deeply pigmented"
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}