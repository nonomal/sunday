import SwiftUI
import CoreLocation
import UIKit
import SwiftData
import WidgetKit
import Combine
import UserNotifications

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var uvService: UVService
    @EnvironmentObject var vitaminDCalculator: VitaminDCalculator
    @EnvironmentObject var healthManager: HealthManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showClothingPicker = false
    @State private var showSunscreenPicker = false
    @State private var showSkinTypePicker = false
    @State private var todaysTotal: Double = 0
    @State private var currentGradientColors: [Color] = []
    @State private var showInfoSheet = false
    @State private var showManualExposureSheet = false
    @State private var showSessionCompletionSheet = false
    @State private var pendingSessionStartTime: Date?
    @State private var pendingSessionAmount: Double = 0
    @State private var lastUVUpdate: Date = UserDefaults.standard.object(forKey: "lastUVUpdate") as? Date ?? Date()
    @State private var timerCancellable: AnyCancellable?
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common)
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            GeometryReader { geometry in
                if uvService.hasNoData {
                    // No data available view
                    VStack(spacing: 20) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("No Data Available")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                            Text("Location access is required to get UV data")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                            
                            Button(action: {
                                locationManager.openSettings()
                            }) {
                                Text("Open Settings")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(25)
                            }
                        } else {
                            Text("Connect to the internet to fetch UV data")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                            
                            if locationManager.location != nil {
                                Button(action: {
                                    if let location = locationManager.location {
                                        uvService.fetchUVData(for: location)
                                    }
                                }) {
                                    Text("Retry")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 30)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.2))
                                        .cornerRadius(25)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            headerSection
                            uvSection
                            vitaminDSection
                            exposureToggle
                            HStack(spacing: 12) {
                                clothingSection
                                sunscreenSection
                            }
                            skinTypeSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                        .padding(.bottom, uvService.isOfflineMode ? 40 : 0)
                    .animation(.easeInOut(duration: 0.3), value: uvService.isOfflineMode)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                        .frame(width: geometry.size.width)
                    }
                    .scrollDisabled(contentFitsInScreen(geometry: geometry))
                }
            }
            
            // Offline mode indicator as thin bar at bottom
            if uvService.isOfflineMode && !uvService.hasNoData {
                VStack {
                    Spacer()
                    HStack(spacing: 7) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 14))
                        if let lastUpdate = uvService.lastSuccessfulUpdate {
                            Text("Offline • Using cached data from \(timeAgo(from: lastUpdate))")
                        } else {
                            Text("Offline • No cached data")
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .padding(.bottom, 20)
                    .background(Color.orange.opacity(0.9))
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: uvService.isOfflineMode)
        .onAppear {
            setupApp()
            // Start timer when view appears
            timerCancellable = timer.autoconnect().sink { _ in
                updateData()
                loadTodaysTotal()
                // Only update gradient if colors actually changed
                let newColors = gradientColors
                if newColors != currentGradientColors {
                    currentGradientColors = newColors
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Check for updated skin type and adaptation when app returns to foreground
            vitaminDCalculator.setHealthManager(healthManager)
            // NetworkMonitor will automatically detect when network is restored
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Resume timer when app becomes active
                timerCancellable = timer.autoconnect().sink { _ in
                    updateData()
                    loadTodaysTotal()
                    // Only update gradient if colors actually changed
                    let newColors = gradientColors
                    if newColors != currentGradientColors {
                        currentGradientColors = newColors
                    }
                }
                // Also update data immediately when returning to foreground
                updateData()
                loadTodaysTotal()
                // Update gradient immediately when returning to foreground
                let newColors = gradientColors
                if newColors != currentGradientColors {
                    currentGradientColors = newColors
                }
                // Restart location updates when app becomes active
                locationManager.startUpdatingLocation()
            case .inactive, .background:
                // Cancel timer when app goes to background
                timerCancellable?.cancel()
                timerCancellable = nil
            @unknown default:
                break
            }
        }
        .onChange(of: vitaminDCalculator.isInSun) {
            handleSunToggle()
        }
        .onChange(of: locationManager.location) { _, newLocation in
            if let location = newLocation {
                uvService.fetchUVData(for: location)
            }
        }
        .onChange(of: vitaminDCalculator.clothingLevel) {
            // Update rate when clothing changes
            vitaminDCalculator.updateUV(uvService.currentUV)
        }
        .onChange(of: vitaminDCalculator.sunscreenLevel) {
            // Update rate when sunscreen changes
            vitaminDCalculator.updateUV(uvService.currentUV)
        }
        .onChange(of: vitaminDCalculator.skinType) {
            // Update rate when skin type changes
            vitaminDCalculator.updateUV(uvService.currentUV)
        }
        .onChange(of: uvService.currentUV) { _, newUV in
            // Update rate when UV changes
            vitaminDCalculator.updateUV(newUV)
        }
        .onOpenURL { url in
            handleURL(url)
        }
        .alert("Location Access Required", isPresented: $locationManager.showLocationDeniedAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Open Settings") {
                locationManager.openSettings()
            }
        } message: {
            Text(locationManager.locationDeniedMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Reset the alert flag when app becomes active (user may have changed settings)
            locationManager.resetLocationDeniedAlert()
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: currentGradientColors.isEmpty ? [Color(hex: "4a90e2"), Color(hex: "7bb7e5")] : currentGradientColors,
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
        Button(action: { showInfoSheet = true }) {
            Text("SUN DAY")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .tracking(2)
        }
    }
    
    private var uvSection: some View {
        VStack(spacing: 8) {
            if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                VStack(spacing: 10) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.7))
                    Text("LOCATION ACCESS REQUIRED")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .tracking(1.5)
                    Button(action: {
                        locationManager.openSettings()
                    }) {
                        Text("Enable Location")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(20)
                    }
                }
            } else {
                Text("UV INDEX")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1.5)
                
                Text(String(format: "%.1f", uvService.currentUV))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            HStack(spacing: 15) {
                VStack(spacing: 3) {
                    Text("BURN LIMIT")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(uvService.currentUV == 0 ? "---" : formatSafeTime(safeExposureTime))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text(" ")
                        .font(.system(size: 8, weight: .medium))
                        .opacity(0)
                }
                
                VStack(spacing: 3) {
                    Text(uvService.shouldShowTomorrowTimes ? "MAX TMRW" : "MAX UVI")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(String(format: "%.1f", uvService.displayMaxUV))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text(" ")
                        .font(.system(size: 8, weight: .medium))
                        .opacity(0)
                }
                
                VStack(spacing: 3) {
                    Text("SUNRISE")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(formatTime(uvService.displaySunrise))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    if uvService.shouldShowTomorrowTimes {
                        Text("TOMORROW")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        Text(" ")
                            .font(.system(size: 8, weight: .medium))
                            .opacity(0)
                    }
                }
                
                VStack(spacing: 3) {
                    Text("SUNSET")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(formatTime(uvService.displaySunset))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    if uvService.shouldShowTomorrowTimes {
                        Text("TOMORROW")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    } else {
                        Text(" ")
                            .font(.system(size: 8, weight: .medium))
                            .opacity(0)
                    }
                }
            }
            
            // Show cloud/altitude/location info
            VStack(spacing: 2) {
                HStack(spacing: 15) {
                    HStack(spacing: 5) {
                        Image(systemName: uvService.currentUV == 0 ? 
                                         (uvService.currentCloudCover < 70 ? moonPhaseIcon() : "cloud.fill") :
                                         uvService.currentCloudCover == 0 ? "sun.max" : 
                                         uvService.currentCloudCover > 50 ? "cloud.fill" : "cloud")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(Int(uvService.currentCloudCover))% clouds")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
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
                    }
                }
                
                // Location name
                if !locationManager.locationName.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                        Text(locationManager.locationName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.top, 3)
            
            
            // Vitamin D winter warning
            if uvService.isVitaminDWinter {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vitamin D Winter")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.yellow)
                        Text("Limited UV-B at \(Int(uvService.currentLatitude))°. Consider supplements.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(10)
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.2))
        .cornerRadius(20)
    }
    
    private var exposureToggle: some View {
        HStack(spacing: 12) {
            // Main tracking button
            Button(action: {
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                if vitaminDCalculator.isInSun && vitaminDCalculator.sessionVitaminD > 0 {
                    // Ending session - show completion sheet
                    // Store session data BEFORE toggling (which might clear it)
                    pendingSessionStartTime = vitaminDCalculator.sessionStartTime
                    pendingSessionAmount = vitaminDCalculator.sessionVitaminD
                    // Don't toggle yet - let the sheet handle it
                    showSessionCompletionSheet = true
                } else {
                    // Starting session - just toggle
                    vitaminDCalculator.toggleSunExposure(uvIndex: uvService.currentUV)
                }
            }) {
                HStack {
                    Image(systemName: vitaminDCalculator.isInSun ? "sun.max.fill" : 
                                     uvService.currentUV == 0 ? moonPhaseIcon() : "sun.max")
                        .font(.system(size: 24))
                        .symbolEffect(.pulse, isActive: vitaminDCalculator.isInSun)
                    
                    Text(vitaminDCalculator.isInSun ? "End" : 
                         uvService.currentUV == 0 ? "No UV available" : "Begin")
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
            
            // Manual entry button
            Button(action: {
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                
                showManualExposureSheet = true
            }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 60)
                    .padding(.vertical, 20)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(15)
            }
            .disabled(vitaminDCalculator.isInSun) // Can't add manual entry while tracking
            .opacity(vitaminDCalculator.isInSun ? 0.4 : 1.0)
        }
    }
    
    private var clothingSection: some View {
        Button(action: { showClothingPicker.toggle() }) {
            VStack(spacing: 10) {
                Text("CLOTHING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1.5)
                
                HStack {
                    Text(vitaminDCalculator.clothingLevel.shortDescription)
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
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    private var sunscreenSection: some View {
        Button(action: { showSunscreenPicker.toggle() }) {
            VStack(spacing: 10) {
                Text("SUNSCREEN")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1.5)
                
                HStack {
                    Text(vitaminDCalculator.sunscreenLevel.description)
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
            SunscreenPicker(selection: $vitaminDCalculator.sunscreenLevel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
                    if vitaminDCalculator.skinTypeFromHealth {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
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
        .sheet(isPresented: $showInfoSheet) {
            InfoSheet()
        }
        .sheet(isPresented: $showManualExposureSheet) {
            ManualExposureSheet()
        }
        .sheet(isPresented: $showSessionCompletionSheet) {
            ZStack {
                // Match the ManualExposureSheet background to avoid any white flash
                LinearGradient(
                    colors: [Color(hex: "4a90e2"), Color(hex: "7bb7e5")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if let startTime = pendingSessionStartTime {
                    SessionCompletionSheet(
                        sessionStartTime: startTime,
                        sessionAmount: pendingSessionAmount,
                        onSave: {
                            // End the session and reset
                            // Reset session amount first to avoid re-presenting the sheet
                            vitaminDCalculator.sessionVitaminD = 0.0
                            vitaminDCalculator.toggleSunExposure(uvIndex: uvService.currentUV)
                            loadTodaysTotal()
                        },
                        onCancel: {
                            // Keep tracking - session continues
                        }
                    )
                    .environmentObject(vitaminDCalculator)
                    .environmentObject(healthManager)
                    .environment(\.modelContext, modelContext)
                } else {
                    // Fallback placeholder to ensure non-empty content during first frame
                    ProgressView().tint(.white)
                }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.clear)
        }
    }
    
    private var vitaminDSection: some View {
        VStack(spacing: 15) {
            HStack(alignment: .top, spacing: 15) {
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
                    
                    Text(formatVitaminDNumber(vitaminDCalculator.currentVitaminDRate / 60.0))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .frame(minWidth: 80)
                        .frame(height: 34)
                    
                    Text("IU/min")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(height: 16)
                }
                .frame(minWidth: 100)
                
                VStack(spacing: 8) {
                    Text("SESSION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(1.2)
                        .frame(height: 12)
                    
                    HStack(spacing: 4) {
                        Text(formatVitaminDNumber(vitaminDCalculator.sessionVitaminD))
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .monospacedDigit()
                            .frame(minWidth: 80, alignment: .trailing)
                        
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
                    Text("TODAY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(1.2)
                        .frame(height: 12)
                    
                    Text(formatTodaysTotal(todaysTotal + vitaminDCalculator.sessionVitaminD))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .frame(minWidth: 80)
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
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
    
    private var safeExposureTime: Int {
        uvService.burnTimeMinutes[vitaminDCalculator.skinType.rawValue] ?? 60
    }
    
    private func setupApp() {
        locationManager.requestPermission()
        healthManager.requestAuthorization()
        loadTodaysTotal()
        currentGradientColors = gradientColors
        // Request notification permissions once up front (for burn warnings and sun events)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        // Connect services - MUST set modelContext before any UV data fetching
        vitaminDCalculator.setHealthManager(healthManager)
        vitaminDCalculator.setUVService(uvService)
        uvService.setModelContext(modelContext)
        uvService.setNetworkMonitor(networkMonitor)
        
        // Fetch UV data on startup
        if let location = locationManager.location {
            uvService.fetchUVData(for: location)
        }
        
        // Initialize vitamin D rate with current UV (even if 0)
        vitaminDCalculator.updateUV(uvService.currentUV)
        
        // If session was restored, start tracking timer
        if vitaminDCalculator.isInSun {
            vitaminDCalculator.startSession(uvIndex: uvService.currentUV)
        }
        
        // Ensure moon phase is available for widget
        if uvService.currentMoonPhaseName.isEmpty {
            let defaultPhase = "Waxing Gibbous"
            uvService.currentMoonPhaseName = defaultPhase
            UserDefaults(suiteName: "group.sunday.widget")?.set(defaultPhase, forKey: "moonPhaseName")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    private func updateData() {
        guard let location = locationManager.location else { return }
        
        // Update UV data every 5 minutes if needed
        let now = Date()
        if now.timeIntervalSince(lastUVUpdate) >= 300 {
            uvService.fetchUVData(for: location)
            lastUVUpdate = now
            UserDefaults.standard.set(now, forKey: "lastUVUpdate")
            
            // Stop high-frequency location updates after getting fresh data
            // Switch to significant location changes for battery efficiency
            locationManager.stopUpdatingLocation()
            locationManager.startSignificantLocationChanges()
        }
        
        vitaminDCalculator.updateUV(uvService.currentUV)
    }
    
    private func handleSunToggle() {
        // Only show completion sheet when turning off tracking from main UI,
        // not while the completion sheet itself is already presented.
        if !vitaminDCalculator.isInSun && vitaminDCalculator.sessionVitaminD > 0 && !showSessionCompletionSheet {
            // Store session data for the completion sheet
            pendingSessionStartTime = vitaminDCalculator.sessionStartTime
            pendingSessionAmount = vitaminDCalculator.sessionVitaminD
            
            // Show the completion sheet
            showSessionCompletionSheet = true
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
        } else if value < 1000 {
            return "\(Int(value))"
        } else if value < 100000 {
            // Add comma formatting for readability (shared formatter)
            return Formatters.decimal.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        } else {
            // Handle very large numbers with K notation
            return String(format: "%.0fK", value / 1000)
        }
    }
    
    private func formatTodaysTotal(_ value: Double) -> String {
        if value < 1000 {
            return "\(Int(value))"
        } else if value < 100000 {
            // Add comma formatting for readability (shared formatter)
            return Formatters.decimal.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        } else {
            return String(format: "%.0fK", value / 1000)
        }
    }

    private enum Formatters {
        static let decimal: NumberFormatter = {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            return f
        }()
    }
    
    private func sessionDurationString(from startTime: Date) -> String {
        let duration = Date().timeIntervalSince(startTime)
        let minutes = Int(duration / 60)
        
        if minutes == 0 {
            return "< 1 min"
        } else if minutes == 1 {
            return "1 min"
        } else {
            return "\(minutes) mins"
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let duration = Date().timeIntervalSince(date)
        let minutes = Int(duration / 60)
        let hours = Int(duration / 3600)
        
        if minutes < 1 {
            return "just now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else if hours < 24 {
            return "\(hours)h ago"
        } else {
            return "\(hours / 24)d ago"
        }
    }
    
    private func handleURL(_ url: URL) {
        guard url.scheme == "sunday" else { return }
        
        switch url.host {
        case "toggle":
            // Only toggle if UV > 0, matching the main app behavior
            if uvService.currentUV > 0 {
                if vitaminDCalculator.isInSun && vitaminDCalculator.sessionVitaminD > 0 {
                    // Ending session - show completion sheet
                    // Store session data BEFORE toggling (which might clear it)
                    pendingSessionStartTime = vitaminDCalculator.sessionStartTime
                    pendingSessionAmount = vitaminDCalculator.sessionVitaminD
                    // Don't toggle yet - let the sheet handle it
                    showSessionCompletionSheet = true
                } else {
                    // Starting session - just toggle
                    vitaminDCalculator.toggleSunExposure(uvIndex: uvService.currentUV)
                }
            }
        default:
            break
        }
    }
    
    private func moonPhaseIcon() -> String {
        // Use the phase name from the API to select the correct icon
        let phaseName = uvService.currentMoonPhaseName.lowercased()
        
        // Map phase names to SF Symbols
        // Note: Farmsense API has typo "Cresent" instead of "Crescent"
        let icon: String
        if phaseName.contains("new") {
            icon = "moonphase.new.moon"
        } else if phaseName.contains("waxing") && phaseName.contains("cres") {
            icon = "moonphase.waxing.crescent"
        } else if phaseName.contains("first quarter") {
            icon = "moonphase.first.quarter"
        } else if phaseName.contains("waxing") && phaseName.contains("gibbous") {
            icon = "moonphase.waxing.gibbous"
        } else if phaseName.contains("full") {
            icon = "moonphase.full.moon"
        } else if phaseName.contains("waning") && phaseName.contains("gibbous") {
            icon = "moonphase.waning.gibbous"
        } else if phaseName.contains("last quarter") || phaseName.contains("third quarter") {
            icon = "moonphase.last.quarter"
        } else if phaseName.contains("waning") && phaseName.contains("cres") {
            icon = "moonphase.waning.crescent"
        } else {
            // Fallback based on illumination if phase name doesn't match
            if uvService.currentMoonPhase > 0.85 {
                icon = "moonphase.full.moon"
            } else {
                icon = "moon"
            }
        }
        
        return icon
    }
    
    private func formatSafeTime(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) hr"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }
    
    private func contentFitsInScreen(geometry: GeometryProxy) -> Bool {
        // Estimate content height
        let estimatedHeight: CGFloat = 40 + 250 + 140 + 70 + 70 + 70 + 40 // header + UV + vitD + button + clothing + skin + padding
        let offlineBarHeight: CGFloat = uvService.isOfflineMode ? 50 : 0
        return estimatedHeight + offlineBarHeight < geometry.size.height
    }
}

struct ClothingPicker: View {
    @Binding var selection: ClothingLevel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
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
            .preferredColorScheme(.dark)
        }
        .presentationBackground(Color(UIColor.systemBackground).opacity(0.99))
    }
}

struct SkinTypePicker: View {
    @Binding var selection: SkinType
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var vitaminDCalculator: VitaminDCalculator
    
    var body: some View {
        NavigationView {
            List {
                ForEach(SkinType.allCases, id: \.self) { type in
                    Button(action: {
                        selection = type
                        dismiss()
                    }) {
                        HStack {
                            Circle()
                                .fill(skinColor(for: type))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                            
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
                            .padding(.leading, 8)
                            
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
            .navigationTitle("Fitzpatrick Skin Type")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .preferredColorScheme(.dark)
            .safeAreaInset(edge: .bottom) {
                if vitaminDCalculator.skinTypeFromHealth {
                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14))
                        Text("Synced from Apple Health")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(UIColor.secondarySystemBackground))
                }
            }
        }
        .presentationBackground(Color(UIColor.systemBackground).opacity(0.99))
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
    
    private func skinColor(for type: SkinType) -> Color {
        switch type {
        case .type1: return Color(red: 1.0, green: 0.92, blue: 0.84)      // Very fair
        case .type2: return Color(red: 0.98, green: 0.87, blue: 0.73)     // Fair
        case .type3: return Color(red: 0.94, green: 0.78, blue: 0.63)     // Light brown
        case .type4: return Color(red: 0.82, green: 0.63, blue: 0.48)     // Moderate brown
        case .type5: return Color(red: 0.63, green: 0.47, blue: 0.36)     // Dark brown
        case .type6: return Color(red: 0.4, green: 0.26, blue: 0.18)      // Very dark brown
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

struct InfoSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var vitaminDCalculator: VitaminDCalculator
    @EnvironmentObject var uvService: UVService
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // About the calculation
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About")
                            .font(.headline)
                        
                        Text("Sun Day uses a scientifically-based multi-factor model to estimate vitamin D synthesis from UV exposure.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("The calculation considers UV intensity, time of day, clothing coverage, skin type, age, and recent exposure history.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Base rate: 21,000 IU/hr (minimal clothing, ~80% exposure)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Link("View detailed methodology", destination: URL(string: "https://github.com/jackjackbits/sunday/blob/main/METHODOLOGY.md")!)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    // Current Calculation Factors
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Current Factors")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            FactorRow(
                                label: "UV Factor",
                                value: String(format: "%.2fx", (uvService.currentUV * 3.0) / (4.0 + uvService.currentUV)),
                                detail: "Non-linear response curve"
                            )
                            
                            FactorRow(
                                label: "UV Quality",
                                value: String(format: "%.0f%%", vitaminDCalculator.currentUVQualityFactor * 100),
                                detail: "Time of day effectiveness"
                            )
                            
                            FactorRow(
                                label: "Clothing",
                                value: String(format: "%.0f%%", vitaminDCalculator.clothingLevel.exposureFactor * 100),
                                detail: vitaminDCalculator.clothingLevel.description
                            )
                            
                            FactorRow(
                                label: "Sunscreen",
                                value: String(format: "%.0f%%", vitaminDCalculator.sunscreenLevel.uvTransmissionFactor * 100),
                                detail: vitaminDCalculator.sunscreenLevel.description
                            )
                            
                            FactorRow(
                                label: "Skin Type",
                                value: String(format: "%.0f%%", vitaminDCalculator.skinType.vitaminDFactor * 100),
                                detail: vitaminDCalculator.skinType.description
                            )
                            
                            if vitaminDCalculator.userAge != nil {
                                FactorRow(
                                    label: "Age Factor",
                                    value: String(format: "%.0f%%", calculateAgeFactor() * 100),
                                    detail: "Age \(vitaminDCalculator.userAge!)"
                                )
                            }
                            
                            FactorRow(
                                label: "Adaptation",
                                value: String(format: "%.1fx", vitaminDCalculator.currentAdaptationFactor),
                                detail: "Based on 7-day history"
                            )
                            
                            if uvService.currentAltitude > 100 {
                                FactorRow(
                                    label: "Altitude",
                                    value: String(format: "+%.0f%%", (uvService.uvMultiplier - 1) * 100),
                                    detail: "\(Int(uvService.currentAltitude))m elevation"
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    // Data sources
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Data Sources")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: "location.circle.fill")
                                .foregroundColor(.blue)
                            Text("Location from device GPS")
                                .font(.caption)
                        }
                        
                        HStack {
                            Image(systemName: "sun.max.fill")
                                .foregroundColor(.orange)
                            Text("UV data from Open-Meteo")
                                .font(.caption)
                        }
                        
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                            Text("Health data from Apple Health")
                                .font(.caption)
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("How It Works")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .preferredColorScheme(.dark)
        }
        .presentationBackground(Color(UIColor.systemBackground).opacity(0.99))
    }
    
    private func calculateAgeFactor() -> Double {
        guard let age = vitaminDCalculator.userAge else {
            return 1.0
        }
        
        if age <= 20 {
            return 1.0
        } else if age >= 70 {
            return 0.25
        } else {
            // Match the calculator's age slope (~1% per year after 20)
            return max(0.25, 1.0 - Double(age - 20) * 0.01)
        }
    }
}

struct FactorRow: View {
    let label: String
    let value: String
    let detail: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
    }
}
