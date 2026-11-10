# Do Notation

Chain steps that need the values of the steps before them.

`ResultDo` chains steps that need the values of the steps before them. `bind` adds a step that returns a `Result`, and `let` adds a plain value. Each closure gets all the values so far. The chain stops at the first failure.

```swift
func order(userID: Int, itemID: Int) -> Result<Order, AppError> {
    ResultDo<AppError>()
        .bind { fetchUser(id: userID) }
        .bind { user in fetchItem(id: itemID) }
        .let { user, item in item.price * user.discount }
        .map { user, item, price in
            Order(user: user, item: item, price: price)
        }
}
```

`bindAsync` and `letAsync` take async closures. You can mix them with `bind` and `let` in one chain. A chain holds up to 10 values.

<!-- Made from README.md by Scripts/make-docc-articles.swift. Edit README.md, then run the script. -->
