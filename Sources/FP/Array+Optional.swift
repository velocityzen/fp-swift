import Foundation

public extension Array {
    /// Returns a new array with all `nil` elements removed.
    ///
    /// Idiomatic shorthand for `compactMap { $0 }`.
    ///
    /// ```swift
    /// let xs: [Int?] = [1, nil, 2, nil, 3]
    /// xs.compact()  // [1, 2, 3]
    /// ```
    func compact<T>() -> [T] where Element == T? {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            if let value = element {
                values.append(value)
            }
        }
        return values
    }

    /// Flips an array of optionals into an optional array — "all or nothing".
    /// Returns `nil` if any element is `nil`; otherwise returns the array of
    /// unwrapped values.
    ///
    /// Partner of ``compact()``: `compact` drops nils, `sequence` rejects on nil.
    ///
    /// ```swift
    /// let xs: [Int?] = [1, 2, 3]
    /// xs.sequence()  // [1, 2, 3]
    ///
    /// let ys: [Int?] = [1, nil, 3]
    /// ys.sequence()  // nil
    /// ```
    func sequence<T>() -> [T]? where Element == T? {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            guard let value = element else { return nil }
            values.append(value)
        }
        return values
    }
}
