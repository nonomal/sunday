import Foundation
import SwiftUI

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension Calendar {
    func isDateInTomorrow(_ date: Date) -> Bool {
        return isDate(date, inSameDayAs: Date().addingTimeInterval(86400))
    }
}