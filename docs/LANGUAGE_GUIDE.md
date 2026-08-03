# KorE Language Reference Manual & Complete Usage Guide

**KorE** is a Kotlin-flavoured programming language designed for the Erlang Virtual Machine (BEAM). It transpiles directly into clean, type-annotated Elixir source code, giving you Kotlin's expressiveness alongside Erlang/OTP's rock-solid fault tolerance and concurrency.

---

## Table of Contents

1. [Program Structure & Modules](#1-program-structure--modules)
2. [Keywords Index](#2-keywords-index)
3. [Variables & Immutability (`val` vs `var`)](#3-variables--immutability-val-vs-var)
4. [Functions (`fun`) & Expressions](#4-functions-fun--expressions)
5. [Data Records (`data`) & Sealed Types (`sealed`)](#5-data-records-data--sealed-types-sealed)
6. [Pattern Matching (`when`, `is`, `else`)](#6-pattern-matching-when-is-else)
7. [Control Flow (`if`, `else`, `for`, `in`, `return`)](#7-control-flow-if-else-for-in-return)
8. [Null-Safety (`null`, `?`, `?.`, `?:`, `!!`)](#8-null-safety-null----elvis---not-null)
9. [Collections, Pairs (`to`), and Literals](#9-collections-pairs-to-and-literals)
10. [Actors (`actor`) & Concurrency (`spawn`, `receive`)](#10-actors-actor--concurrency-spawn-receive)
11. [Interoperability (`import elixir...`)](#11-interoperability-import-elixir)
12. [Built-in Prelude Reference](#12-built-in-prelude-reference)

---

## 1. Program Structure & Modules

Every `.kore` file belongs to a module defined by the `module` keyword. File names must match the snake_case representation of the module name (e.g., `user_service.kore` must contain `module UserService`).

```kotlin
import elixir.IO

module UserService {
    fun greet(name: String): String = "Hello, $name!"
}
```

---

## 2. Keywords Index

KorE features 21 reserved keywords:

| Keyword | Description & Usage |
|---|---|
| `module` | Declares a module namespace. |
| `import` | Imports external Elixir or KorE modules. |
| `fun` | Declares a named function or method. |
| `val` | Declares an immutable local variable, record property, or parameter. |
| `var` | Declares a rebindable (mutable) local variable, record property, or actor field. |
| `data` | Declares an immutable data record class (Elixir struct). |
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
| `to` | Pair constructor operator (`a to b`). |

---

## 3. Variables & Immutability (`val` vs `var`)

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

## 4. Functions (`fun`) & Expressions

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
    fun power(base: Int, exponent: Int = 2): Int {
        // ...
    }
}
```

### Lambdas & Higher-Order Functions
Lambdas are defined inside braces `{ params -> body }`. If a lambda has a single argument and no parameter list is specified, it is implicitly named `it`:

```kotlin
val numbers = listOf(1, 2, 3, 4, 5)

// Implicit 'it' parameter
val doubled = numbers.map { it * 2 }

// Explicit parameters
val sum = numbers.fold(0) { acc, x -> acc + x }
```

---

## 5. Data Records (`data`) & Sealed Types (`sealed`)

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
        data Point
    }

    fun area(s: Shape): Double = when (s) {
        is Circle(val r) -> 3.14159 * r * r
        is Rect(val w, val h) -> w * h
        is Point -> 0.0
    }
}
```

> [!IMPORTANT]
> The `when` expression over a `sealed` type enforces **compile-time exhaustiveness**. Omitting any variant without providing an `else` branch will produce a compilation error.

---

## 6. Pattern Matching (`when`, `is`, `else`)

The `when` expression provides rich pattern matching capabilities:

### Value Matching
```kotlin
fun describeNumber(n: Int): String = when (n) {
    0 -> "zero"
    1, 2 -> "small"
    in 3..10 -> "medium"
    else -> "large"
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

## 7. Control Flow (`if`, `else`, `for`, `in`, `return`)

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

## 8. Null-Safety (`null`, `?`, `?.`, `?:`, `!!`)

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

    return safeBio.length()
}
```

---

## 9. Collections, Pairs (`to`), and Literals

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

## 10. Actors (`actor`) & Concurrency (`spawn`, `receive`)

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
        val pid = Counter.start(10)
        Counter.increment(pid)
        Counter.add(pid, 5)
        println("Current count: ${Counter.get(pid)}") // 16
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

## 11. Interoperability (`import elixir...`)

Call standard Elixir modules or Hex packages directly in KorE:

```kotlin
import elixir.IO
import elixir.String as ExString

module InteropDemo {
    fun log(msg: String) {
        IO.puts("LOG: " + msg)
    }
}
```

---

## 12. Built-in Prelude Reference

KorE automatically imports common stdlib methods for `List`, `Map`, `String`, and `Result`:

| KorE Expression | Generated Elixir Translation |
|---|---|
| `list.map { ... }` | `Enum.map(list, fn ... end)` |
| `list.filter { ... }` | `Enum.filter(list, fn ... end)` |
| `list.fold(init) { acc, x -> ... }` | `Enum.reduce(list, init, fn x, acc -> ... end)` |
| `list.length()` | `length(list)` |
| `str.uppercase()` | `String.upcase(str)` |
| `str.lowercase()` | `String.downcase(str)` |
| `str.trim()` | `String.trim(str)` |
| `str.length()` | `String.length(str)` |
| `map.get(key)` | `Map.get(map, key)` |
| `listOf(a, b)` | `[a, b]` |
| `mapOf(k to v)` | `%{k => v}` |
| `Ok(v)` | `{:ok, v}` |
| `Error(e)` | `{:error, e}` |

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
