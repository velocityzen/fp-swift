/**
 * Result+Bool - Boolean Conversion for Result Type
 *
 * Provides a simple way to convert a Result to a boolean value,
 * useful for conditional checks where you only care about success/failure.
 *
 * Usage:
 *   let result = someOperation()
 *   if result.toBool {
 *       print("Operation succeeded")
 *   }
 *
 *   // Or in ternary expressions
 *   let message = result.toBool ? "ok" : "error"
 */
import Foundation

public extension Result {
    /// Returns `true` if the result is a success, `false` if it's a failure.
    var toBool: Bool {
        switch self {
            case .success:
                return true
            case .failure:
                return false
        }
    }
}
