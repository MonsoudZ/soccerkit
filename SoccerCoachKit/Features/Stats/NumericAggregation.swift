import Foundation

extension Collection where Element == Int {
    /// The arithmetic mean as a `Double`, or `nil` when the collection is empty.
    /// Shared by the season/development/readiness aggregators.
    var average: Double? {
        isEmpty ? nil : Double(reduce(0, +)) / Double(count)
    }
}
