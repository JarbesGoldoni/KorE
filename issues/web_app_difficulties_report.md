# KorE Difficulties Report
### Discovered during: web chat app implementation (2026-08-04)

---

## Summary

I attempted to build a minimal group chat web app using KorE + Plug/Cowboy. The `kore check` (syntax/semantic validation) passed cleanly for all files, but multiple issues appeared during actual Elixir compilation (`kore build`) and would appear at runtime. Here is the full catalogue of what I found.

---

## 1. Multi-line `data` and `actor` declarations are not supported

**What I expected:**
```kotlin
data Message(
    val id: Int,
    val user: String,
    val text: String,
    val timestamp: String
)
```

**What actually happened:**
```
Expected 'val', got newline
```

The parser requires all `data` fields and all `actor` fields to be on a single line. Neither the LANGUAGE_GUIDE nor REFERENCE docs mention this restriction. This makes it tedious for records with many fields.

**Impact:** Minor — workaround is to inline, but it's very unreadable.

---

## 2. `data` is a reserved keyword — cannot use it as a bound variable in `when`/`is` patterns

**What I expected:**
```kotlin
val json = Jason.encode(msgs)
val body = when (json) {
    is Ok(val data) -> data   // 'data' is a keyword!
    else -> "[]"
}
```

**What actually happened:** Parse error — `data` is a KorE keyword, so it cannot be used as a bound variable name inside `is Ok(val data)`.

**Impact:** Moderate — you have to rename the variable (e.g. `encoded`, `bodyStr`), but this is a footgun because the error message isn't immediately obvious.

---

## 3. String escape sequences (`\"`) are silently stripped in generated Elixir

**What I expected:** Writing `\"` inside a KorE string to embed a double-quote in a string literal — the generated Elixir would contain `\"`.

**What actually happened:** The generated Elixir code strips the backslash, producing unescaped `"` characters directly in the Elixir source, which terminates the string early and causes a parse error in `mix compile`.

**Example:**
- KorE source: `"<html lang=\"en\">"` 
- Generated Elixir: `"<html lang="en">"` ← breaks Elixir parser

**Impact:** Severe. This makes it impossible to embed double-quoted content (HTML attributes, JSON literals, etc.) directly in KorE strings. The only workarounds are:
- Use unquoted HTML attributes (valid HTML5 but ugly)
- Use HTML entities (`&quot;`)
- Avoid any `"` in string content at all

---

## 4. KorE `kore check` does NOT catch generated-Elixir compile errors

**What I expected:** `kore check` to validate the full pipeline including detecting whether the generated Elixir would compile.

**What actually happened:** `kore check` reported `0 errors found in 4 file(s)` even when the generated Elixir had multiple hard syntax errors. The check only validates KorE-level syntax and semantics, not whether the resulting Elixir is actually valid.

**Impact:** Severe for development workflow. The feedback loop is:
1. Edit `.kore`
2. `kore check` → passes ✅
3. `kore build` → Elixir compile fails ❌
4. Debug generated `.ex` file (which you're not supposed to edit)

There is no way to know if generated Elixir is valid without running the full build.

---

## 5. `word:` patterns inside string literals cause Elixir keyword argument parse errors

**What I expected:** Strings containing CSS or URL content like `background: var(--bg)` or `https://fonts.googleapis.com` to be safe inside KorE string literals.

**What actually happened:** When KorE generates string concatenation with `+`, and the string contains patterns like `background:` or `https:`, Elixir's parser interprets `word:` as a keyword argument syntax error — even though it's inside a string.

**Root cause:** The `+` operator in KorE for strings generates `+` in Elixir (not `<>`). Elixir then parses the entire expression including string boundaries in a way that treats `word:` as keyword args.

**Affected patterns:**
- CSS: `background:`, `color:`, `border:`, `font-size:`, etc.
- URLs: `https:`, `http:`
- Any `word:value` pattern in a concatenated string context

**Impact:** Severe. Made it impossible to include CSS or external URLs in strings that also contain `+` concatenation with variables. Required restructuring the entire HTML serving approach.

---

## 6. `+` is generated for string concatenation instead of `<>` 

**What I expected:** `"hello" + name + "!"` in KorE to generate valid Elixir string concatenation.

**What actually happened:** The generated Elixir uses `+` for string concatenation:
```elixir
"hello" + name + "!"
```
But in Elixir, `+` is numeric-only. String concatenation requires `<>`. At runtime this would raise `ArithmeticError` when strings are passed to `+`.

The compiler only generated a warning (not an error) about type incompatibility, but would crash at runtime on any path that constructs strings via `+`.

**Impact:** Severe. String building via `+` — a core operation for serving HTML — is broken at runtime. This makes KorE essentially unusable for web app development without workarounds.

---

## 7. Nested module type references are not supported in type annotations

**What I expected:** Being able to declare a variable with a dotted type across modules:
```kotlin
val store: ChatStore.Store = opts
```

**What actually happened:**
```
Expected '=', got '.'
```

The KorE type grammar only allows a single `TypeName` (no dots). This means you cannot type-annotate cross-module actor references. This severely limits cross-module actor usage.

**Impact:** Severe. When an actor from module `ChatStore` is passed as `Any` to another module, the KorE compiler cannot recognize it as an actor and doesn't generate the proper `GenServer.call/cast` dispatch — it generates a plain local function call instead.

---

## 8. Actor method dispatch breaks when the actor is typed as `Any`

**What I expected:** Calling `store.getMessages()` where `store: Any` to work via the Elixir Plug's opts mechanism.

**What actually happened:** Because `store` is typed `Any`, the KorE compiler generates:
```elixir
get_messages(store)   # treated as a local function call
```
instead of:
```elixir
GenServer.call(store, :get_messages)   # the correct actor dispatch
```

This generates an `undefined function` compile error.

**Impact:** Severe. Without dotted type support (issue #7), there is no way in KorE to correctly call actor methods on an actor defined in a different module when that actor is received as a parameter typed `Any`.

---

## 9. `Conn.getMethod` and `Conn.getPathInfo` are generated but don't exist in Plug

**What I expected:** `Conn.getMethod(conn)` and `Conn.getPathInfo(conn)` to map to valid Plug.Conn functions.

**What actually happened:** The generated Elixir calls `Conn.get_method(conn)` and `Conn.get_path_info(conn)`, which don't exist in Plug.Conn. The correct Elixir patterns are:
- `conn.method` (struct field access)
- `conn.path_info` (struct field access)

These are struct fields, not function calls. The KorE prelude doesn't document which Plug.Conn functions are available, and there's no way to access struct fields directly in KorE syntax.

**Impact:** Severe. The entire HTTP routing mechanism doesn't work at runtime because the conn data can't be read.

---

## 10. `Conn.readBody` return value mismatch

**What I expected:** `Conn.readBody(conn)` to return `{:ok, body_string}`, matching the `is Ok(val bodyStr)` pattern.

**What actually happened:** Plug's `Plug.Conn.read_body/2` returns `{:ok | :more, data, conn}` — a 3-tuple, not a 2-tuple. So `is Ok(val bodyStr)` never matches.

**Impact:** Moderate — body reading always falls through to the `else` branch, returning empty string. POST message handling silently fails.

---

## 11. Nested `data` type code generation bug: wrong module name

**What I expected:** `data Message` inside `module ChatStore` to generate `Kore.ChatStore.Message.new(...)`.

**What actually happened:** The generated code calls `Kore.Message.new(...)` — the `ChatStore` namespace prefix is dropped. This produces a runtime `UndefinedFunctionError`.

**Impact:** Severe. The core `ChatStore.Store.addMessage` actor handler crashes on every call because it tries to create a `Kore.Message` struct that doesn't exist.

---

## 12. `ChatStore.Store.start()` vs `Kore.ChatStore.Store.start()` in `main.kore`

**What I expected:** `ChatStore.Store.start()` to be the correct way to call the actor start function from another module.

**What actually happened:** The generated `main.ex` calls `ChatStore.Store.start()` but the actual module is `Kore.ChatStore.Store`. This is a naming consistency bug — within a module, actor names work without the `Kore.` prefix, but cross-module calls don't get the prefix resolved correctly.

**Impact:** Moderate — workaround is to use the full Elixir interop path `import elixir.Kore.ChatStore.Store`.

---

## 13. `receive { else -> { ... it ... } }` — `it` is not bound in `else` branches

**What I expected:** Based on the LANGUAGE_GUIDE example of `receive { is String -> println(it) }`, I assumed `it` is the implicit name for the matched value in any receive branch.

**What actually happened:** In an `else ->` branch (wildcard), the received message is NOT bound to `it`. The generated Elixir has `_ ->` which discards the value. Only `is TypeName -> ...` branches bind to `it`.

**Impact:** Moderate for SSE/receive-based patterns. You cannot use the received value in an `else` branch.

---

## 14. `\n` escape sequences are not supported in strings

**What I expected:** `"data: " + encoded + "\n\n"` to produce a string with actual newlines.

**What actually happened:** The `\n` is treated as a literal backslash-n in the string (KorE docs say raw string literals `"""` are not supported, but they don't clearly state that `\n` escape sequences don't work either). The generated Elixir contains literal `\n` character sequences instead of newlines.

**Impact:** Moderate — affects SSE format which requires `\n\n` as delimiter.

---

## 15. The `Pair(:atom, value)` constructor for GenServer cast messages has unexpected nesting

**What I expected:** `GenServer.cast(store, Pair(:add_message, Pair(user, Pair(text, ts))))` to generate `{:add_message, user, text, ts}`.

**What actually happened:** The generated Elixir is `{:add_message, {user, {text, ts}}}` — nested tuples, which doesn't match the `handle_cast({:add_message, user, text, timestamp}, state)` pattern in the actor.

**Impact:** Moderate — requires knowing the exact generated pattern to write compatible cast messages.

---

## Overall Assessment

| Category | Severity | Status |
|---|---|---|
| `kore check` doesn't validate generated Elixir | 🔴 Severe | No workaround |
| String `\"` escaping stripped | 🔴 Severe | Workaround: avoid `"` in strings |
| `+` for strings generates invalid Elixir | 🔴 Severe | No clean workaround |
| Dotted type names not supported | 🔴 Severe | No workaround |
| Actor dispatch broken across modules | 🔴 Severe | Workaround: direct GenServer interop |
| Nested data type naming bug | 🔴 Severe | No workaround |
| Plug.Conn struct field access missing | 🔴 Severe | No workaround in KorE |
| `word:` in strings triggers keyword error | 🟠 High | Workaround: restructure strings |
| `it` not bound in `else` receive branch | 🟡 Medium | Workaround: use `is TypeName` |
| `Conn.readBody` return type mismatch | 🟡 Medium | Workaround: handle in else branch |
| Multi-line data/actor declarations | 🟢 Low | Workaround: inline |
| `data` keyword conflicts with variable names | 🟢 Low | Workaround: rename variable |

**Conclusion:** KorE v0.1 is currently not production-ready for web applications. The core blocker is that `kore check` passes but generated Elixir fails to compile or crashes at runtime for basic operations. The most critical missing features for web development are: struct field access for Plug.Conn, working string concatenation (`<>` not `+`), cross-module actor type references, and reliable string escaping.
