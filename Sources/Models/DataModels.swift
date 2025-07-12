import Foundation
import SwiftData

@Model
final class UserPreferences {
    var clothingLevel: Int = 1 // Default to light clothing
    var skinType: Int = 3 // Default to type 3
    var userAge: Int = 30
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    init(clothingLevel: Int = 1, skinType: Int = 3, userAge: Int = 30) {
        self.clothingLevel = clothingLevel
        self.skinType = skinType
        self.userAge = userAge
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class VitaminDSession {
    var startTime: Date
    var endTime: Date?
    var totalIU: Double
    var averageUV: Double
    var peakUV: Double
    var clothingLevel: Int
    var skinType: Int
    
    init(startTime: Date, totalIU: Double = 0, averageUV: Double = 0, peakUV: Double = 0, clothingLevel: Int, skinType: Int) {
        self.startTime = startTime
        self.totalIU = totalIU
        self.averageUV = averageUV
        self.peakUV = peakUV
        self.clothingLevel = clothingLevel
        self.skinType = skinType
    }
}

@Model
final class CachedUVData {
    var latitude: Double
    var longitude: Double
    var date: Date
    var hourlyUVData: Data? // Store as JSON data
    var hourlyCloudCoverData: Data? // Store as JSON data
    var maxUV: Double
    var sunrise: Date
    var sunset: Date
    var lastUpdated: Date
    
    // Computed properties to convert between Array and Data
    var hourlyUV: [Double] {
        get {
            guard let data = hourlyUVData else { return [] }
            return (try? JSONDecoder().decode([Double].self, from: data)) ?? []
        }
        set {
            hourlyUVData = try? JSONEncoder().encode(newValue)
        }
    }
    
    var hourlyCloudCover: [Double] {
        get {
            guard let data = hourlyCloudCoverData else { return [] }
            return (try? JSONDecoder().decode([Double].self, from: data)) ?? []
        }
        set {
            hourlyCloudCoverData = try? JSONEncoder().encode(newValue)
        }
    }
    
    init(latitude: Double, longitude: Double, date: Date, hourlyUV: [Double], hourlyCloudCover: [Double], maxUV: Double, sunrise: Date, sunset: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
        self.hourlyUVData = try? JSONEncoder().encode(hourlyUV)
        self.hourlyCloudCoverData = try? JSONEncoder().encode(hourlyCloudCover)
        self.maxUV = maxUV
        self.sunrise = sunrise
        self.sunset = sunset
        self.lastUpdated = Date()
    }
}