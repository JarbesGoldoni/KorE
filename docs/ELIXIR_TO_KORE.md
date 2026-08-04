# Elixir → KorE Translation Guide

## The Protocol

When writing KorE code, follow this mental model:
1. **Think in Elixir**: design the solution using Elixir idioms (GenServers, pattern matching, tagged tuples, Enum pipelines)
2. **Translate**: convert each construct using the tables below
3. **Validate**: run `kore check` for fast feedback

---

## Module & Function Structure

| Elixir | KorE |
|--------|------|
| `defmodule MyApp.UserService do ... end` | `module UserService { ... }` |
| `def greet(name) do ... end` | `fun greet(name: String): String { ... }` |
| `def add(a, b), do: a + b` | `fun add(a: Int, b: Int): Int = a + b` |
| `def scale(x, factor \\ 2)` | `fun scale(x: Int, factor: Int = 2)` |
| `@spec greet(String.t()) :: String.t()` | (auto-generated from type annotations) |

## Variables & Bindings

| Elixir | KorE |
|--------|------|
| `name = "diego"` (never rebound) | `val name: String = "diego"` |
| `count = 0; count = count + 1` (rebound) | `var count = 0; count = count + 1` |
| `x = x + 1` | `x += 1` |

## Data Structures

| Elixir | KorE |
|--------|------|
| `defstruct [:name, :age]` with `@enforce_keys` | `data User(val name: String, val age: Int = 0)` |
| `%User{name: "diego", age: 30}` | `User("diego", 30)` |
| `%{user \| age: 31}` | `user.copy(age = 31)` |
| Sealed/tagged union: multiple structs + `@type t :: A.t() \| B.t()` | `sealed Shape { data Circle(val r: Double) data Rect(val w: Double, val h: Double) }` |

## Pattern Matching

| Elixir | KorE |
|--------|------|
| `case x do ... end` | `when (x) { ... }` |
| `%Circle{r: r} -> ...` | `is Circle(val r) -> ...` |
| `{:ok, value} -> ...` | `is Ok(val value) -> ...` |
| `{:error, reason} -> ...` | `is Error(val reason) -> ...` |
| `n when n in [1, 2] -> ...` | `1, 2 -> ...` |
| `_ -> ...` | `else -> ...` |

## Control Flow

| Elixir | KorE |
|--------|------|
| `if cond, do: a, else: b` | `if (cond) a else b` |
| `if cond do ... else ... end` | `if (cond) { ... } else { ... }` |
| `Enum.each(list, fn x -> ... end)` | `for (x in list) { ... }` |
| `for i <- 1..10, do: ...` | `for (i in 1..10) { ... }` |

## Collections & Enum

| Elixir | KorE |
|--------|------|
| `[1, 2, 3]` | `listOf(1, 2, 3)` |
| `%{"a" => 1, "b" => 2}` | `mapOf("a" to 1, "b" to 2)` |
| `{a, b}` | `Pair(a, b)` or `a to b` |
| `Enum.map(list, fn x -> x * 2 end)` | `list.map { it * 2 }` |
| `Enum.filter(list, fn x -> x > 0 end)` | `list.filter { it > 0 }` |
| `Enum.reduce(list, 0, fn x, acc -> acc + x end)` | `list.fold(0) { acc, x -> acc + x }` |
| `Enum.each(list, fn x -> IO.puts(x) end)` | `list.forEach { println(it) }` |
| `length(list)` | `list.size` |
| `Enum.empty?(list)` | `list.isEmpty()` |
| `Enum.reverse(list)` | `list.reversed()` |
| `Enum.sort(list)` | `list.sorted()` |
| `Enum.join(list, ", ")` | `list.joinToString(", ")` |
| `list ++ [item]` | `list.plus(item)` |
| `list1 ++ list2` | `list.plusAll(list2)` |
| `Enum.take(list, n)` | `list.take(n)` |
| `Enum.drop(list, n)` | `list.drop(n)` |
| `Enum.sum(list)` | `list.sum()` |
| `x in list` | `list.contains(x)` or `x in list` |
| `Map.get(map, key)` | `map.get(key)` |
| `Map.put(map, key, val)` | `map.put(key, val)` |
| `Map.delete(map, key)` | `map.remove(key)` |
| `Map.has_key?(map, key)` | `map.containsKey(key)` |
| `Map.keys(map)` | `map.keys` |
| `Map.values(map)` | `map.values` |

## Strings

| Elixir | KorE |
|--------|------|
| `"Hello, #{name}"` | `"Hello, $name"` |
| `"sum: #{a + b}"` | `"sum: ${a + b}"` |
| `String.length(s)` | `s.length` |
| `String.upcase(s)` | `s.uppercase()` |
| `String.downcase(s)` | `s.lowercase()` |
| `String.trim(s)` | `s.trim()` |
| `String.split(s, ",")` | `s.split(",")` |
| `String.starts_with?(s, "pre")` | `s.startsWith("pre")` |
| `String.ends_with?(s, "suf")` | `s.endsWith("suf")` |
| `String.replace(s, "a", "b")` | `s.replace("a", "b")` |
| `String.to_integer(s)` | `s.toInt()` |
| `to_string(x)` | `x.toString()` |

## Null Safety (nil handling)

| Elixir | KorE |
|--------|------|
| `case x do nil -> default; v -> v end` | `x ?: default` |
| `case x do nil -> nil; v -> v.field end` | `x?.field` |
| `case x do nil -> raise "null"; v -> v end` | `x!!` |
| `@type t :: String.t() \| nil` | `String?` |

## Result / Tagged Tuples

| Elixir | KorE |
|--------|------|
| `{:ok, value}` | `Ok(value)` |
| `{:error, reason}` | `Error(reason)` |
| `{:ok, value} \| {:error, reason}` (as @type) | `Result<Value, Reason>` |
| `case result do {:ok, v} -> ... {:error, e} -> ... end` | `when (result) { is Ok(val v) -> ... is Error(val e) -> ... }` |

## Concurrency

| Elixir | KorE |
|--------|------|
| `spawn(fn -> ... end)` | `spawn { ... }` |
| `send(pid, msg)` | `pid.send(msg)` |
| `self()` | `self()` |
| `receive do ... end` | `receive { ... }` |
| GenServer (full module) | `actor Name(var state: T = default) { fun method() { ... } }` |
| `GenServer.cast` | Actor method returning `Unit` (no return type) |
| `GenServer.call` | Actor method with a return type |
| `GenServer.start_link` | `ActorName.start()` or `ActorName.start(initialState)` |

## Interop

| Elixir | KorE |
|--------|------|
| `alias Plug.Conn` | `import elixir.Plug.Conn` |
| `Plug.Conn.send_resp(conn, 200, "ok")` | `Conn.sendResp(conn, 200, "ok")` |
| `IO.puts("hello")` | `println("hello")` |
| Keyword list `[port: 4000]` | `listOf(Pair(:port, 4000))` |
| Atoms `:ok`, `:error` | `:ok`, `:error` |

## Recursion (replaces while loops)

Since KorE has no `while`, use recursive functions:

```kotlin
// Elixir:
// def loop(state) do
//   case get_input() do
//     "quit" -> state
//     input -> loop(process(state, input))
//   end
// end

module App {
    fun loop(state: String): String {
        val input = readLine()
        return when (input) {
            "quit" -> state
            else -> loop(process(state, input))
        }
    }
}
```

## Worked Example: Key-Value Cache

Elixir (GenServer):
```elixir
defmodule Cache do
  use GenServer
  def start_link(_), do: GenServer.start_link(__MODULE__, %{})
  def put(pid, k, v), do: GenServer.cast(pid, {:put, k, v})
  def get(pid, k), do: GenServer.call(pid, {:get, k})
  def init(state), do: {:ok, state}
  def handle_cast({:put, k, v}, state), do: {:noreply, Map.put(state, k, v)}
  def handle_call({:get, k}, _from, state), do: {:reply, Map.get(state, k), state}
end
```

KorE equivalent:
```kotlin
module CacheApp {
    actor Cache(var store: Map<String, String> = mapOf()) {
        fun put(key: String, value: String) {
            store = store.put(key, value)
        }
        fun get(key: String): String? = store.get(key)
    }

    fun main() {
        val c = Cache.start()
        c.put("lang", "KorE")
        val v = c.get("lang") ?: "unknown"
        println("Got: $v")
    }
}
```
