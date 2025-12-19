import Foundation

public extension Result {
    static func fromOptional(_ optional: Success?, error: Failure) -> Result<Success, Failure> {
        if let value = optional {
            return .success(value)
        } else {
            return .failure(error)
        }
    }

    static func fromOptional(_ optional: Success?, onError: () -> Failure) -> Result<
        Success, Failure
    > {
        if let value = optional {
            return .success(value)
        } else {
            return .failure(onError())
        }
    }
}
