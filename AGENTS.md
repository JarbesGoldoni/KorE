# KorE — Agent Reference

KorE is Elixir with Kotlin syntax. Think in Elixir/OTP idioms first, then translate.

## Identity

- Kotlin-flavoured language targeting the Erlang VM (BEAM)
- Transpiles `.kore` → Elixir source → BEAM bytecode
- One module per file; file name must match module name in snake_case
- All generated Elixir modules are namespaced under `Kore.`

## Workflow

1. Write `.kore` files in `lib/`
2. Run `kore check` after every edit (fast semantic validation, no codegen)
3. Run `kore build` to transpile + compile to BEAM
4. Run `kore run` to execute `Kore.Main.main()`

## Project anatomy

```
myapp/
├── kore.exs          # [name: "myapp", version: "0.1.0", deps: [...]]
├── lib/
│   ├── main.kore     # entry point: module Main { fun main() { ... } }
│   └── *.kore        # one module per file
└── _build/kore_gen/  # generated Elixir (don't edit)
```

## Quick syntax (full reference: docs/REFERENCE.md)

```kotlin
module MyService {
    data User(val name: String, val age: Int = 0)

    sealed Result {
        data Success(val value: String)
        data Failure(val reason: String)
    }

    fun greet(name: String): String = "Hello, $name"

    fun process(r: Result): String = when (r) {
        is Success(val v) -> "ok: $v"
        is Failure(val reason) -> "err: $reason"
    }

    actor Cache(var store: Map<String, String> = mapOf()) {
        fun put(key: String, value: String) { store = store.put(key, value) }
        fun get(key: String): String? = store.get(key)
    }
}
```

## Top 10 gotchas

1. **No `while`/loops** — use recursion or `list.fold { }` for accumulation
2. **`var` in lambdas is a compile error** — BEAM closures capture values, not variables
3. **`var` in `for` bodies is a compile error** — use `fold` instead
4. **No early return** — `return` only in tail position; use `if`/`when` expressions
5. **File/module naming** — `user_service.kore` must contain `module UserService`
6. **`+=`/`-=` work** — they desugar to `x = x + expr`
7. **Actor rule**: method returns `Unit` → async cast; returns a value → sync call
8. **`Ok(x)`/`Error(e)`** are built-in constructors for `{:ok, x}/{:error, e}` tuples
9. **camelCase → snake_case** — all function/variable names are auto-mangled in output
10. **One module per file** — no multi-module files; nested types become sub-modules

## Not supported (v0.1)

- `while`, `break`, `continue`
- Early `return` (except in last position)
- User-defined generics (only built-in `List<T>`, `Map<K,V>`, `Result<T,E>`)
- Interfaces/traits, extension functions, operator overloading
- `try`/`catch` — use `Result` + pattern matching (let-it-crash philosophy)
- `map[key]` bracket syntax — use `map.get(key)` instead
- `var` fields in `data` records — only `val`

## Translation protocol

For any task, follow this protocol:
1. Draft the solution mentally as idiomatic Elixir
2. Translate using `docs/ELIXIR_TO_KORE.md`
3. Write the `.kore` file
4. Run `kore check` to validate
5. Fix using error messages (see `docs/REFERENCE.md` § Error Catalog)

## Key references

- `docs/REFERENCE.md` — full grammar, types, prelude, errors
- `docs/ELIXIR_TO_KORE.md` — translation table + worked examples
- `examples/` — runnable cookbook projects
