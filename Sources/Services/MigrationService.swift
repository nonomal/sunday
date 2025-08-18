import Foundation
import SwiftData
import OSLog

class MigrationService {
    private static let logger = Logger(subsystem: "it.sunday.app", category: "Migration")
    static func migrateUserDefaults(to modelContext: ModelContext) {
        // Check if migration has already been performed
        let migrationKey = "hasPerformedSwiftDataMigration"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        
        // Fetch any existing preferences
        let descriptor = FetchDescriptor<UserPreferences>()
        let existingPreferences = (try? modelContext.fetch(descriptor)) ?? []
        
        // Only migrate if no preferences exist yet
        if existingPreferences.isEmpty {
            // Migrate clothing level
            let clothingLevel = UserDefaults.standard.object(forKey: "preferredClothingLevel") as? Int ?? 1
            
            // Migrate skin type
            let skinType = UserDefaults.standard.object(forKey: "userSkinType") as? Int ?? 3
            
            // Migrate user age
            let userAge = UserDefaults.standard.object(forKey: "userAge") as? Int ?? 30
            
            // Create new UserPreferences in SwiftData
            let preferences = UserPreferences(
                clothingLevel: clothingLevel,
                skinType: skinType,
                userAge: userAge
            )
            
            modelContext.insert(preferences)
            
            // Save the context
            do {
                try modelContext.save()
            } catch {
                #if DEBUG
                Self.logger.error("Failed to migrate user preferences: \(String(describing: error), privacy: .public)")
                #endif
            }
        }
        
        // Mark migration as complete
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}
