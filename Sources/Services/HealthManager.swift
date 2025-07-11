import Foundation
import HealthKit

class HealthManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var lastError: String?
    
    private let healthStore = HKHealthStore()
    private let vitaminDType = HKQuantityType.quantityType(forIdentifier: .dietaryVitaminD)!
    
    init() {
        checkAuthorizationStatus()
    }
    
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "Health data not available on this device"
            return
        }
        
        let typesToWrite: Set<HKSampleType> = [vitaminDType]
        let typesToRead: Set<HKObjectType> = [vitaminDType]
        
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                self?.lastError = error?.localizedDescription
            }
        }
    }
    
    private func checkAuthorizationStatus() {
        let status = healthStore.authorizationStatus(for: vitaminDType)
        isAuthorized = status == .sharingAuthorized
    }
    
    func saveVitaminD(amount: Double, date: Date = Date()) {
        guard isAuthorized else {
            requestAuthorization()
            return
        }
        
        // Convert IU to micrograms (1 IU = 0.025 mcg)
        let micrograms = amount * 0.025
        let quantity = HKQuantity(unit: .gramUnit(with: .micro), doubleValue: micrograms)
        let sample = HKQuantitySample(
            type: vitaminDType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: [
                HKMetadataKeyWasUserEntered: false,
                "Source": "Sun Day - UV Exposure",
                "Method": "Calculated from UV exposure",
                "OriginalValueInIU": amount
            ]
        )
        
        healthStore.save(sample) { [weak self] success, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }
    
    func getTodaysVitaminD(completion: @escaping (Double?) -> Void) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )
        
        let query = HKStatisticsQuery(
            quantityType: vitaminDType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, error in
            DispatchQueue.main.async {
                if let sum = result?.sumQuantity() {
                    // Convert micrograms back to IU (1 mcg = 40 IU)
                    let micrograms = sum.doubleValue(for: .gramUnit(with: .micro))
                    let iuValue = micrograms * 40.0
                    completion(iuValue)
                } else {
                    completion(nil)
                }
            }
        }
        
        healthStore.execute(query)
    }
}