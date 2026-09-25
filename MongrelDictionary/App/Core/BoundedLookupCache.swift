/// A small actor-confined LRU cache. Misses count toward the same limit as hits,
/// so typing unfamiliar words cannot grow decoded database storage indefinitely.
struct BoundedLookupCache<Key: Hashable, Value> {
    let limit: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    var count: Int { values.count }

    subscript(key: Key) -> Value? {
        mutating get {
            guard let value = values[key] else { return nil }
            touch(key)
            return value
        }
        set {
            guard let newValue, limit > 0 else {
                values.removeValue(forKey: key)
                order.removeAll { $0 == key }
                return
            }
            values[key] = newValue
            touch(key)
            if order.count > limit {
                values.removeValue(forKey: order.removeFirst())
            }
        }
    }

    private mutating func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }
}
