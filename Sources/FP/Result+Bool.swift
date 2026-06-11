/*
 * Result+Bool - Boolean Checks for Result Type
 *
 * Provides simple boolean checks for conditionals where you only care
 * about success/failure.
 *
 * Usage:
 *   let result = someOperation()
 *   if result.isSuccess {
 *       print("Operation succeeded")
 *   }
 *
 *   // Or in ternary expressions
 *   let message = result.isSuccess ? "ok" : "error"
 */
public extension Result {
    /// Returns `true` if the result is a success, `false` if it's a failure.
    var isSuccess: Bool {
        switch self {
            case .success:
                return true
            case .failure:
                return false
        }
    }

    /// Returns `true` if the result is a failure, `false` if it's a success.
    var isFailure: Bool {
        !isSuccess
    }
}
