# Pipe Operators

Pass values through functions with `|>`, `|>>` and `|>>>`.

`x |> f` calls `f(x)`. A chain of them reads in the order the steps run:

```swift
func double(_ n: Int) -> Int { n * 2 }
func label(_ n: Int) -> String { "#\(n)" }

let text = 5 |> double |> label  // "#10"
```

`|>>` passes the value as the second argument, and `|>>>` as the third:

```swift
func add(_ a: Int, _ b: Int) -> Int { a + b }

let sum = 2 |>> (add, 10)  // add(10, 2), so 12
```

The operators also take `async` functions. A chain becomes `async` when one of its steps is:

```swift
let page = await id
    |> normalize  // sync
    |> loadUser   // async
    |> render     // sync
```

The operators bind looser than arithmetic and `??`, but tighter than comparisons and `&&`. So the whole expression on the left goes into the function:

```swift
1 + 2 |> double   // double(3), not 1 + double(2)
x |> double == 6  // (x |> double) == 6
```

<!-- Made from README.md by Scripts/make-docc-articles.swift. Edit README.md, then run the script. -->
