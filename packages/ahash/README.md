# ahash
ahash 哈希函数仓颉实现。

当前仓库内置的是纯仓颉版本，不依赖 AES 指令或本地 FFI。

## 使用
```cangjie
import ahash.{RandomState,AHasher}
...
let builder = RandomState.new()
let hasher = builder.buildHasher()

let a = Array<UInt8>(10,repeat:1)
hasher.write(a)
hasher.write(10101)

let hash = hasher.finish()
println |> hash
```
