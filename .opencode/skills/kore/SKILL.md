# KorE Language Skill

## Trigger
Use this skill when writing `.kore` files, working in a KorE project (has `kore.exs`), or when the user mentions KorE, Kotlin-on-BEAM, or asks about transpiling to Elixir.

## Identity

KorE is Elixir with Kotlin syntax. It transpiles `.kore` → Elixir → BEAM bytecode.

## Mental Model

**Always think in Elixir first, then translate to KorE syntax.**

1. Design the solution as idiomatic Elixir (GenServers, pattern matching, Enum pipelines, tagged tuples)
2. Translate each construct using the mappings below
3. Write the `.kore` file
4. Validate with `kore check` (fast, no codegen)
5. Build with `kore build`

## Quick Reference

### Module structure
```kotlin
module ModuleName {
    fun functionName(param: Type): ReturnType = expression
    fun blockFunction(x: Int) { ... }
}
```
File `module_name.kore` → module `ModuleName` → Elixir `Kore.ModuleName`

### Data & Types
```kotlin
data User(val name: String, val age: Int = 0)     // Elixir struct
sealed Shape { data Circle(val r: Double) data Rect(val w: Double, val h: Double) }
```
Construct: `User("name", 30)`. Update: `user.copy(age = 31)`.

### Pattern matching
```kotlin
when (x) {
    is Circle(val r) -> 3.14 * r * r
    is Ok(val v) -> "got $v"
    is Error(val e) -> "err $e"
    0 -> "zero"
    1, 2 -> "small"
    else -> "other"
}
```

### Actors (GenServer sugar)
```kotlin
actor Counter(var count: Int = 0) {
    fun increment() { count += 1 }     // Unit return = cast (async)
    fun get(): Int = count              // Value return = call (sync)
}
val c = Counter.start()
c.increment()
val n = c.get()
```

### Null safety
- `T?` = nullable, `x?.field` = safe access, `x ?: default` = elvis, `x!!` = force unwrap

### Collections
- `listOf(1,2,3)`, `mapOf("a" to 1)`, `Pair(a, b)` or `a to b`
- Methods: `.map{}`, `.filter{}`, `.fold(init){acc,x->}`, `.forEach{}`, `.size`, `.plus(x)`, `.plusAll(list)`
- Map: `.get(k)`, `.put(k,v)`, `.remove(k)`, `.containsKey(k)`, `.keys`, `.values`

### Concurrency
- `spawn { body }`, `pid.send(msg)`, `receive { is Type -> ... }`, `self()`

### Result
- `Ok(value)` → `{:ok, value}`, `Error(reason)` → `{:error, reason}`
- Match with `is Ok(val v)` / `is Error(val e)` in `when`

### Interop
- `import elixir.Module.Name` at file top, then call `Name.function(args)`
- Atoms: `:name`. Keyword lists: `listOf(Pair(:key, value))`

## Critical Rules (compile errors if violated)

1. `var` CANNOT be rebound inside lambdas (`list.map { x = 1 }` → ERROR)
2. `var` CANNOT be rebound inside `for` bodies → use `fold` instead
3. No early `return` — only in last position of function body
4. One module per file; file name must be `snake_case.kore` matching `module CamelCase`
5. `sealed` type `when` must be exhaustive (cover all variants or use `else`)
6. `data` fields must use `val` (not `var`); only actor fields can be `var`
7. No `while`, `break`, `continue` — use recursion
8. No `map[key]` — use `map.get(key)`

## String interpolation
- `"Hello, $name"` for variables
- `"Result: ${expr + 1}"` for expressions

## Common Patterns

### Recursion (replaces while)
```kotlin
fun loop(state: Int): Int =
    if (state >= 10) state
    else loop(state + 1)
```

### Accumulate with fold (replaces var in loop)
```kotlin
val sum = list.fold(0) { acc, x -> acc + x }
```

### Error handling
```kotlin
fun safeDivide(a: Int, b: Int): Result<Int, String> =
    if (b == 0) Error("division by zero")
    else Ok(a / b)
```

## Prelude (key methods and their Elixir targets)

| KorE | Elixir |
|------|--------|
| `println(x)` | `IO.puts(x)` |
| `tupleOf(a, b, c)` | `{a, b, c}` (flat BEAM tuple) |
| `Conn.getMethod(conn)` | `conn.method` |
| `Conn.getPathInfo(conn)` | `conn.path_info` |
| `Conn.readBody(conn)` | `case Plug.Conn.read_body(conn)...` |
| `list.map { }` | `Enum.map(list, fn)` |
| `list.fold(init) { acc, x -> }` | `Enum.reduce(list, init, fn x, acc -> end)` |
| `map.get(k)` | `Map.get(map, k)` |
| `map.put(k, v)` | `Map.put(map, k, v)` |
| `map.remove(k)` | `Map.delete(map, k)` |
| `s.split(",")` | `String.split(s, ",")` |
| `x.toString()` | `to_string(x)` |
| `list.plus(x)` | `list ++ [x]` |

## References

- Agent guide: `AGENTS.md`
- Full language reference: `docs/REFERENCE.md`
- Translation table: `docs/ELIXIR_TO_KORE.md`
- Examples: `examples/` directory
- Error catalog: `docs/REFERENCE.md` § Error Catalog
