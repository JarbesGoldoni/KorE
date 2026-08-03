# KorE Language Reference Manual & Complete Usage Guide

**KorE** is a Kotlin-flavoured programming language designed for the Erlang Virtual Machine (BEAM). It transpiles directly into clean, type-annotated Elixir source code, giving you Kotlin's expressiveness alongside Erlang/OTP's rock-solid fault tolerance and concurrency.

---

## Table of Contents

1. [CLI Toolchain & Commands](#1-cli-toolchain--commands)
2. [Project Configuration (`kore.exs`)](#2-project-configuration-koreexs)
3. [Program Structure & Modules](#3-program-structure--modules)
4. [Keywords Index](#4-keywords-index)
5. [Variables & Immutability (`val` vs `var`)](#5-variables--immutability-val-vs-var)
6. [Functions (`fun`) & Expressions](#6-functions-fun--expressions)
7. [Data Records (`data`) & Sealed Types (`sealed`)](#7-data-records-data--sealed-types-sealed)
8. [Pattern Matching (`when`, `is`, `else`)](#8-pattern-matching-when-is-else)
9. [Control Flow (`if`, `else`, `for`, `in`, `return`)](#9-control-flow-if-else-for-in-return)
10. [Null-Safety (`null`, `?`, `?.`, `?:`, `!!`)](#10-null-safety-null----elvis---not-null)
11. [Collections, Pairs (`to`), and Literals](#11-collections-pairs-to-and-literals)
12. [Actors (`actor`) & Concurrency (`spawn`, `receive`)](#12-actors-actor--concurrency-spawn-receive)
13. [Interoperability (`import elixir...`)](#13-interoperability-import-elixir)
14. [Complete Built-in Prelude Reference](#14-complete-built-in-prelude-reference)

---

## 1. CLI Toolchain & Commands

The `kore` CLI is the primary developer interface for scaffolding, building, checking, testing, running, and formatting KorE applications.

```bash
kore <command> [options]
```

### Available Commands

| Command | Usage | Description |
|---|---|---|
| `new` | `kore new <name>` | Scaffolds a new KorE project in directory `<name>`. |
| `build` | `kore build` | Transpiles `.kore` files to Elixir (`_build/kore_gen/`) and compiles to `.beam`. |
| `run` | `kore run [module]` | Builds and executes `Kore.Main.main()` or `<module>.main()`. |
| `clean` | `kore clean` | Removes the `_build/` directory and compiled artifacts. |
| `check` | `kore check` | Performs fast syntax and semantic validation without code generation. |
| `test` | `kore test` | Compiles and executes project tests inside the BEAM runtime. |
| `fmt`, `format` | `kore fmt [files] [--check]` | Formats `.kore` source files in-place (`--check` verifies formatting). |
| `version` | `kore version` | Displays the compiler toolchain version. |
| `help` | `kore help [command]` | Displays detailed help for any command. |

#### Command Details

- **`kore clean`**: Cleans all build artifacts by deleting `_build/`.
  ```bash
  $ kore clean
  Cleaned build artifacts (_build/).
  ```

- **`kore check`**: Runs all 6 semantic passes (scopes, closure safety, SSA var-threading, exhaustiveness, minimal type checking) without invoking `mix compile`. Ideal for fast feedback and IDE integration.
  ```bash
  $ kore check
  Check passed: 0 errors found in 2 file(s).
  ```

- **`kore fmt` / `kore format`**: Standard code formatter. Formats code in-place or checks compliance in CI.
  ```bash
  $ kore fmt                  # Format all lib/ and test/ files in-place
  $ kore format --check       # Check formatting status without modifying files
  ```

---

## 2. Project Configuration (`kore.exs`)

Every KorE project contains a `kore.exs` configuration file at the root:

```elixir
[name: "my_app", version: "0.1.0"]
```

When running `kore build`, the compiler synthesizes a `_build/kore_gen/mix.exs` manifest using the application name and version.

---

## 3. Program Structure & Modules

Every `.kore` file belongs to a module defined by the `module` keyword. Module names use `UpperCamelCase`. Generated modules are automatically namespaced under `Kore.` in Elixir (e.g. `module UserService` → `Kore.UserService`).

```kotlin
import elixir.IO

module UserService {
    fun greet(name: String): String = "Hello, $name!"
}
```

---

## 4. Keywords Index

KorE features 21 reserved keywords:

| Keyword | Description & Usage |
|---|---|
| `module` | Declares a module namespace. |
| `import` | Imports external Elixir modules (`import elixir.X.Y`). |
| `fun` | Declares a named function or method. |
| `val` | Declares an immutable local variable, record property, or parameter. |
| `var` | Declares a rebindable local variable or actor state field. |
| `data` | Declares an immutable struct record (`data User(...)`). |
| `sealed` | Declares a closed algebraic sum type (tagged union). |
| `when` | Expression for pattern matching against values or types. |
| `is` | Type test or variant pattern matcher inside `when` / `receive`. |
| `if` | Conditional branching expression. |
| `else` | Fallback branch for `if` and default pattern for `when`. |
| `for` | Loop expression iterating over range or collection (`for (x in list)`). |
| `in` | Membership test (`x in list`) or iterator separator in `for`. |
| `return` | Tail-position return statement from a block. |
| `actor` | Declares an OTP `GenServer` stateful actor process. |
| `spawn` | Spawns a new concurrent BEAM process executing a block/lambda. |
| `receive` | Blocks process execution to match incoming process messages. |
| `true` | Boolean truth literal. |
| `false` | Boolean false literal. |
| `null` | Absence of value for nullable types (`T?`). |
| `to` | Pair constructor binary operator (`a to b`). |

---

## 5. Variables & Immutability (`val` vs `var`)

### `val` (Immutable Binding)
Bindings declared with `val` cannot be reassigned.

```kotlin
val pi: Double = 3.14159
val greeting = "Welcome to KorE"
// pi = 3.14 -> Compile error: cannot reassign 'val' variable 'pi'
```

### `var` (Local Rebinding / Automatic Var-Threading)
`var` allows local reassignment. The KorE compiler automatically transforms `var` reassignments within `if` and `when` blocks into pure SSA tuple transformations:

```kotlin
fun calculateDiscount(items: Int, vip: Boolean): Double {
    var discount = 0.0
    var bonus = 0

    if (vip) {
        discount = 0.20
        bonus = 50
    } else {
        if (items > 10) {
            discount = 0.10
        }
    }

    return discount
}
```

> [!NOTE]
> Rebinding a `var` inside a lambda closure is prohibited (`list.map { x = 2 }` fails compilation) to guarantee thread-safe execution across processes.

---

## 6. Functions (`fun`) & Expressions

Functions can be declared with an expression body (`=`) or a block body (`{ ... }`).

```kotlin
module MathUtils {
    // Single-expression body
    fun add(a: Int, b: Int): Int = a + b

    // Block body with explicit return or last-expression return
    fun max(a: Int, b: Int): Int {
        if (a > b) {
            return a
        } else {
            return b
        }
    }

    // Default arguments
    fun scale(x: Int, factor: Int = 2): Int = x * factor
}
```

### Lambdas & Higher-Order Functions
Lambdas are defined inside braces `{ params -> body }` or `{ body }`. If a lambda has a single argument and no parameter list is specified, it is implicitly named `it`:

```kotlin
val numbers = listOf(1, 2, 3, 4, 5)

// Implicit 'it' parameter
val doubled = numbers.map { it * 2 }

// Explicit parameters
val sum = numbers.fold(0) { acc, x -> acc + x }
```

---

## 7. Data Records (`data`) & Sealed Types (`sealed`)

### `data` (Struct Records)
Data classes define immutable data containers with named fields and automatic `copy(...)` helper synthesis.

```kotlin
module Models {
    data User(val name: String, val age: Int = 0, val email: String? = null)

    fun birthday(u: User): User {
        // Copy with updated properties
        return u.copy(age = u.age + 1)
    }
}
```

### `sealed` (Algebraic Sum Types)
Sealed types define closed variant hierarchies.

```kotlin
module Geometry {
    sealed Shape {
        data Circle(val radius: Double)
        data Rect(val width: Double, val height: Double)
    }

    fun area(s: Shape): Double = when (s) {
        is Circle(val r) -> 3.14159 * r * r
        is Rect(val w, val h) -> w * h
    }
}
```

> [!IMPORTANT]
> The `when` expression over a `sealed` type enforces **compile-time exhaustiveness**. Omitting any variant without providing an `else` branch will produce a compilation error.

---

## 8. Pattern Matching (`when`, `is`, `else`)

The `when` expression provides rich pattern matching capabilities:

### Value Matching
```kotlin
fun describeNumber(n: Int): String = when (n) {
    0 -> "zero"
    1, 2 -> "small"
    else -> "big"
}
```

### Type & Variant Destructuring (`is`)
```kotlin
fun processResult(res: Result<String, Int>): String = when (res) {
    is Ok(val msg) -> "Success: $msg"
    is Error(val code) -> "Failed with code: $code"
}
```

---

## 9. Control Flow (`if`, `else`, `for`, `in`, `return`)

### `if` Expression
In KorE, `if` is an expression that yields a value:

```kotlin
val status = if (score >= 60) "Passed" else "Failed"
```

### `for` Loops & Ranges
`for` iterates over ranges or standard collections:

```kotlin
fun printRange() {
    for (i in 1..5) {
        println(i)
    }

    val names = listOf("Alice", "Bob", "Charlie")
    for (name in names) {
        println("Hello, $name")
    }
}
```

---

## 10. Null-Safety (`null`, `?`, `?.`, `?:`, `!!`)

KorE explicitly separates non-nullable types (`String`) from nullable types (`String?`).

```kotlin
data Profile(val bio: String?)
data User(val profile: Profile?)

fun getBioLength(u: User?): Int {
    // 1. Safe navigation (?.): returns null if u or profile is null
    val bio: String? = u?.profile?.bio

    // 2. Elvis operator (?:): provides default fallback when left is null
    val safeBio: String = bio ?: "No bio provided"

    // 3. Forced unwrap (!!): throws runtime error if value is null
    val forcedBio: String = u!!.profile!!.bio

    return safeBio.length
}
```

---

## 11. Collections, Pairs (`to`), and Literals

### Lists & Maps
```kotlin
// Lists
val numbers: List<Int> = listOf(10, 20, 30)

// Maps & Pairs
val scores: Map<String, Int> = mapOf("Alice" to 95, "Bob" to 88)
val pair: Pair<String, Int> = "Diego" to 100
```

### String Interpolation
Use `$var` for variables and `${expr}` for expressions inside strings:

```kotlin
val item = "Apple"
val price = 2.50
val label = "Item: $item costs $${price * 1.10}"
```

---

## 12. Actors (`actor`) & Concurrency (`spawn`, `receive`)

### OTP Actors (`actor`)
Actors encapsulate state inside isolated BEAM processes (`GenServer`).

```kotlin
module CounterApp {
    actor Counter(var count: Int = 0) {
        // Asynchronous (GenServer.cast) - Unit return
        fun increment() {
            count = count + 1
        }

        fun add(n: Int) {
            count = count + n
        }

        // Synchronous (GenServer.call) - Non-Unit return
        fun get(): Int = count
    }

    fun main() {
        val c = Counter.start(10)
        c.increment()
        c.add(5)
        println("Current count: ${c.get()}") // 16
    }
}
```

### Low-Level Process Primitives (`spawn`, `receive`)
```kotlin
fun workerProcess() {
    val pid = spawn {
        receive {
            is String -> println("Received text: $it")
            is Int -> println("Received number: $it")
        }
    }

    pid.send("Hello process!")
}
```

---

## 13. Interoperability (`import elixir...`)

Call standard Elixir modules or Hex packages directly in KorE:

```kotlin
import elixir.IO
import elixir.Ecto.Repo

module InteropDemo {
    fun log(msg: String) {
        IO.puts("LOG: " + msg)
    }
}
```

---

## 14. Complete Built-in Prelude Reference

KorE automatically maps common standard methods to efficient Elixir functions at compile time:

| KorE Call / Property | Transpiled Elixir Target | Description |
|---|---|---|
| `println(x)` | `IO.puts(x)` | Writes line to stdout. |
| `print(x)` | `IO.write(x)` | Writes string to stdout without newline. |
| `readLine()` | `IO.gets("") \|> String.trim_trailing()` | Reads line from stdin. |
| `listOf(a, b)` | `[a, b]` | Constructs list literal. |
| `mapOf(k to v)` | `%{k => v}` | Constructs map literal. |
| `Pair(a, b)` / `a to b` | `{a, b}` | Constructs 2-tuple pair. |
| `list.map { }` | `Enum.map(list, fn)` | Maps elements over list. |
| `list.filter { }` | `Enum.filter(list, fn)` | Filters elements by predicate. |
| `list.forEach { }` | `Enum.each(list, fn)` | Executes block for each element. |
| `list.fold(init) { acc, x -> }` | `Enum.reduce(list, init, fn x, acc -> end)` | Reduces collection with accumulator. |
| `list.size` | `length(list)` | List element count property. |
| `list.first()` | `List.first(list)` | Returns first element or `nil`. |
| `list.last()` | `List.last(list)` | Returns last element or `nil`. |
| `list.isEmpty()` | `Enum.empty?(list)` | Returns `true` if list is empty. |
| `list.contains(x)` / `x in list` | `x in list` | Membership test. |
| `list.reversed()` | `Enum.reverse(list)` | Reverses list elements. |
| `list.sorted()` | `Enum.sort(list)` | Sorts list elements. |
| `list.joinToString(sep)` | `Enum.join(list, sep)` | Joins elements into single string. |
| `s.length` | `String.length(s)` | String length property. |
| `s.uppercase()` | `String.upcase(s)` | Converts string to uppercase. |
| `s.lowercase()` | `String.downcase(s)` | Converts string to lowercase. |
| `s.trim()` | `String.trim(s)` | Strips leading/trailing whitespace. |
| `s.split(sep)` | `String.split(s, sep)` | Splits string into list by separator. |
| `s.startsWith(p)` | `String.starts_with?(s, p)` | Returns `true` if string starts with prefix. |
| `s.toInt()` | `String.to_integer(s)` | Parses string as integer. |
| `x.toString()` | `to_string(x)` | Converts value to string representation. |
| `map.get(k)` / `map[k]` | `Map.get(map, k)` | Map lookup by key. |
| `map.put(k, v)` | `Map.put(map, k, v)` | Returns updated map with key-value. |
| `map.keys` | `Map.keys(map)` | Returns list of map keys. |
| `map.values` | `Map.values(map)` | Returns list of map values. |
| `Ok(v)` | `{:ok, v}` | Success tagged tuple for `Result<T, E>`. |
| `Error(e)` | `{:error, e}` | Error tagged tuple for `Result<T, E>`. |

---

## Summary Cheat Sheet

```kotlin
module QuickRef {
    // 1. Data model
    data User(val name: String, var score: Int = 0)

    // 2. Function with expression body
    fun isTopScorer(u: User): Boolean = u.score >= 100

    // 3. Pattern matching & SSA var-threading
    fun update(u: User, points: Int): User {
        var newScore = u.score
        if (points > 0) {
            newScore = newScore + points
        }
        return u.copy(score = newScore)
    }
}
```
