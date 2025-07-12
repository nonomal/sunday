import Foundation
import Combine
import HealthKit

enum ClothingLevel: Int, CaseIterable {
    case none = -1
    case minimal = 0
    case light = 1
    case moderate = 2
    case heavy = 3
    
    var description: String {
        switch self {
        case .none: return "Nude!"
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
            // If user manually changes skin type, it's no longer from Health
            if !isSettingFromHealth {
                skinTypeFromHealth = false
            }
        }
    }
    @Published var currentVitaminDRate: Double = 0.0
    @Published var sessionVitaminD: Double = 0.0
    @Published var sessionStartTime: Date?
    @Published var skinTypeFromHealth = false
    @Published var userAge: Int = 30 {
        didSet {
            UserDefaults.standard.set(userAge, forKey: "userAge")
        }
    }
    @Published var ageFromHealth = false
    
    private var timer: Timer?
    private var lastUV: Double = 0.0
    private var healthManager: HealthManager?
    private var isSettingFromHealth = false
    
    init() {
        loadUserPreferences()
    }
    
    func setHealthManager(_ healthManager: HealthManager) {
        self.healthManager = healthManager
        checkHealthKitSkinType()
        checkHealthKitAge()
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
        
        if let savedAge = UserDefaults.standard.object(forKey: "userAge") as? Int {
            userAge = savedAge
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
        
        // Age factor: vitamin D synthesis decreases with age
        // ~25% synthesis at age 70 compared to age 20
        let ageFactor: Double
        if userAge <= 20 {
            ageFactor = 1.0
        } else if userAge >= 70 {
            ageFactor = 0.25
        } else {
            // Linear decrease: lose ~1.5% per year after age 20
            ageFactor = max(0.25, 1.0 - Double(userAge - 20) * 0.015)
        }
        
        // Final calculation: base * UV * clothing * skin type * age
        currentVitaminDRate = baseRate * uvFactor * exposureFactor * skinFactor * ageFactor
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
    
    private func checkHealthKitSkinType() {
        healthManager?.getFitzpatrickSkinType { [weak self] hkSkinType in
            guard let self = self, let hkSkinType = hkSkinType else { return }
            
            // Map HealthKit Fitzpatrick skin type to our SkinType enum
            let mappedSkinType: SkinType?
            switch hkSkinType {
            case .I:
                mappedSkinType = .type1
            case .II:
                mappedSkinType = .type2
            case .III:
                mappedSkinType = .type3
            case .IV:
                mappedSkinType = .type4
            case .V:
                mappedSkinType = .type5
            case .VI:
                mappedSkinType = .type6
            case .notSet:
                mappedSkinType = nil
            @unknown default:
                mappedSkinType = nil
            }
            
            // If we got a valid skin type from Health, use it
            if let mappedSkinType = mappedSkinType {
                self.isSettingFromHealth = true
                self.skinType = mappedSkinType
                self.skinTypeFromHealth = true
                self.isSettingFromHealth = false
            } else {
                self.skinTypeFromHealth = false
            }
        }
    }
    
    private func checkHealthKitAge() {
        healthManager?.getAge { [weak self] age in
            guard let self = self, let age = age else { return }
            
            self.userAge = age
            self.ageFromHealth = true
            
            // Recalculate vitamin D rate with new age
            self.updateVitaminDRate(uvIndex: self.lastUV)
        }
    }
}
