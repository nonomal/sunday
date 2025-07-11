import SwiftUI

@main
struct SundayApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var healthManager = HealthManager()
    @StateObject private var uvService = UVService()
    @StateObject private var vitaminDCalculator = VitaminDCalculator()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(healthManager)
                .environmentObject(uvService)
                .environmentObject(vitaminDCalculator)
        }
    }
}