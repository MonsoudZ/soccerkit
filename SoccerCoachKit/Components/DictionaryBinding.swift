import SwiftUI

extension ObservableObject where Self: AnyObject {
    /// A two-way binding into one entry of a published dictionary, creating a
    /// default entry on first write. Centralizes the per-player form binding
    /// shared by the post-game report and the match questionnaires:
    ///
    ///     entryBinding(\.reports, key: playerID, default: GamePlayerReport(), \.goals)
    func entryBinding<Key: Hashable, Item, Value>(
        _ dictionary: ReferenceWritableKeyPath<Self, [Key: Item]>,
        key: Key,
        default makeDefault: @escaping @autoclosure () -> Item,
        _ field: WritableKeyPath<Item, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self[keyPath: dictionary][key, default: makeDefault()][keyPath: field] },
            set: { self[keyPath: dictionary][key, default: makeDefault()][keyPath: field] = $0 }
        )
    }
}
