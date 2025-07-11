import Foundation
import Combine

enum ClothingLevel: Int, CaseIterable {
    case none = -1
    case minimal = 0
    case light = 1
    case moderate = 2
    case heavy = 3
    
    var description: String {
        switch self {
        case .none: return "No clothing"
        case .minimal: return "Minimal (swimwear)"
        case .light: return "Light (shorts & t-shirt)"
        case .moderate: return "Moderate (long sleeves)"
        case .heavy: return "Heavy (fully covered)"
        }
    }
    
    var exposureFactor: Double {
        switch self {
        case .none: return 0.90
        case .minimal: return 0.75
        case .light: return 0.40
        case .moderate: return 0.15
        case .heavy: return 0.05
        }
    }
}

enum SkinType: Int, CaseIterable {
    case type1 = 1
    case type2 = 2
    case type3 = 3
    case type4 = 4
    case type5 = 5
    case type6 = 6
    
    var description: String {
        switch self {
        case .type1: return "Very fair"
        case .type2: return "Fair"
        case .type3: return "Light"
        case .type4: return "Medium"
        case .type5: return "Dark"
        case .type6: return "Very dark"
        }
    }
    
    var vitaminDFactor: Double {
        switch self {
        case .type1: return 1.0
        case .type2: return 0.85
        case .type3: return 0.7
        case .type4: return 0.5
        case .type5: return 0.3
        case .type6: return 0.15
        }
    }
}

class VitaminDCalculator: ObservableObject {
    @Published var isInSun = false
    @Published var clothingLevel: ClothingLevel = .light {
        didSet {
            UserDefaults.standard.set(clothingLevel.rawValue, forKey: "preferredClothingLevel")
        }
    }
    @Published var skinType: SkinType = .type3 {
        didSet {
            UserDefaults.standard.set(skinType.rawValue, forKey: "userSkinType")
        }
    }
    @Published var currentVitaminDRate: Double = 0.0
    @Published var sessionVitaminD: Double = 0.0
    @Published var sessionStartTime: Date?
    
    private var timer: Timer?
    private var lastUV: Double = 0.0
    
    init() {
        loadUserPreferences()
    }
    
    private func loadUserPreferences() {
        if let savedClothingLevel = UserDefaults.standard.object(forKey: "preferredClothingLevel") as? Int,
           let clothing = ClothingLevel(rawValue: savedClothingLevel) {
            clothingLevel = clothing
        }
        
        if let savedSkinType = UserDefaults.standard.object(forKey: "userSkinType") as? Int,
           let skin = SkinType(rawValue: savedSkinType) {
            skinType = skin
        }
    }
    
    func startSession(uvIndex: Double) {
        guard isInSun else { return }
        
        sessionStartTime = Date()
        sessionVitaminD = 0.0
        lastUV = uvIndex
        
        // Update every second for real-time display
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateVitaminD(uvIndex: self?.lastUV ?? 0)
        }
        
        updateVitaminDRate(uvIndex: uvIndex)
    }
    
    func stopSession() {
        timer?.invalidate()
        timer = nil
        sessionStartTime = nil
    }
    
    func updateUV(_ uvIndex: Double) {
        lastUV = uvIndex
        updateVitaminDRate(uvIndex: uvIndex)
    }
    
    private func updateVitaminDRate(uvIndex: Double) {
        // Always calculate the rate to show potential vitamin D gain
        // Base rate: 1000 IU/hr is conservative estimate for moderate exposure
        // Studies show 10,000-20,000 IU possible with full body summer sun exposure
        let baseRate = 1000.0
        
        // UV factor: linear up to UV 3, then capped at 2x multiplier
        // UV 0 = 0x, UV 1.5 = 0.5x, UV 3+ = 2x
        let uvFactor = min(uvIndex / 3.0, 2.0)
        
        // Exposure based on clothing coverage
        let exposureFactor = clothingLevel.exposureFactor
        
        // Skin type affects vitamin D synthesis efficiency
        let skinFactor = skinType.vitaminDFactor
        
        // Final calculation: base * UV * clothing * skin type
        currentVitaminDRate = baseRate * uvFactor * exposureFactor * skinFactor
    }
    
    private func updateVitaminD(uvIndex: Double) {
        guard isInSun else { return }
        
        updateVitaminDRate(uvIndex: uvIndex)
        // Divide by 3600 since we're updating every second (hourly rate / 3600 seconds)
        sessionVitaminD += currentVitaminDRate / 3600.0
    }
    
    func toggleSunExposure(uvIndex: Double) {
        isInSun.toggle()
        
        if isInSun {
            startSession(uvIndex: uvIndex)
        } else {
            stopSession()
        }
    }
}