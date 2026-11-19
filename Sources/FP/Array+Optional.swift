public extension Array {
    /// Returns the array without its `nil` elements.
    ///
    /// Same as `compactMap { $0 }`.
    @inlinable
    func compact<T>() -> [T] where Element == T? {
        if count >= DirectFill.minimumCount, _isPOD(T.self) {
            return trivialValues { $0 }
        }

        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            if let value = element {
                values.append(value)
            }
        }
        return values
    }

    /// Returns the unwrapped values, or `nil` if any element is `nil`.
    ///
    /// To drop the `nil` elements instead, use ``compact()``.
    ///
    /// ```swift
    /// let xs: [Int?] = [1, nil, 3]
    /// xs.sequence()  // nil
    /// ```
    @inlinable
    func sequence<T>() -> [T]? where Element == T? {
        guard count >= DirectFill.minimumCount else {
            var values: [T] = []
            values.reserveCapacity(count)
            for element in self {
                guard let value = element else { return nil }
                values.append(value)
            }
            return values
        }

        var sawNil = false
        let values = [T](capacity: count) { (output: inout OutputSpan<T>) in
            for element in self {
                guard let value = element else {
                    sawNil = true
                    return
                }
                output.append(value)
            }
        }
        return sawNil ? nil : values
    }
}
