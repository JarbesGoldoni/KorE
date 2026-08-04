# KorE — Implementation Specification v0.1 (MVP)

KorE is a Kotlin-flavoured language that targets the Erlang VM (BEAM) by
transpiling to Elixir source code. Its goal is to bring JVM developers into
the Erlang ecosystem with familiar syntax while producing idiomatic Elixir/OTP
underneath.

This document is a complete, self-contained specification for implementing the
KorE MVP compiler and toolchain. An implementing agent should be able to build
the project from this document alone.

---

## 1. High-level architecture

```
 .kore files
     │
     ▼
 ┌───────────┐   ┌───────────┐   ┌──────────────────┐   ┌───────────────┐
 │  Lexer    │──▶│  Parser   │──▶│ Semantic passes  │──▶│ Elixir codegen│
 └───────────┘   └───────────┘   └──────────────────┘   └───────────────┘
   tokens          KorE AST        resolved/rewritten       .ex files in
                                   AST                      _build/kore_gen/
                                                                 │
                                                                 ▼
                                                          mix compile → .beam
```

- **Implementation language of the compiler: Elixir**, structured as a Mix
  project at the repository root.
- **Compilation pipeline**: `.kore` → Elixir source (hidden in
  `_build/kore_gen/`) → compiled by the Elixir compiler via Mix → `.beam`.
- The user interacts only with the `kore` CLI (`kore new | build | run`);
  generated Elixir is an internal artifact (but human-readable for debugging).

### Design principles

1. KorE is a *thin skin* over Elixir. Every construct has a direct, readable
   Elixir mapping.
2. Immutability by default; `var` means **rebinding**, never mutation.
3. Generated code must be idiomatic Elixir (pattern matching, guards,
   GenServers), so escape hatches and debugging feel natural.
4. Interop feels native: the KorE prelude wraps the Elixir stdlib; users never
   see `Enum`/`Map` etc. unless they opt in via `import elixir.X`.

---

## 2. Repository layout

```
KorE/
├── mix.exs                     # Mix project: app :kore
├── lib/
│   ├── kore/
│   │   ├── cli.ex              # escript entry point (kore new/build/run)
│   │   ├── lexer.ex
│   │   ├── parser.ex
│   │   ├── ast.ex              # AST node structs
│   │   ├── semantics/
│   │   │   ├── scopes.ex       # name resolution, val/var tracking
│   │   │   ├── var_threading.ex# SSA-style var rewrite (§7.4)
│   │   │   ├── closures.ex     # forbid var mutation in lambdas
│   │   │   └── exhaustive.ex   # sealed-type when exhaustiveness
│   │   ├── typecheck.ex        # minimal local checks (§10)
│   │   ├── codegen/
│   │   │   ├── elixir.ex       # AST → Elixir source (pretty printer)
│   │   │   ├── specs.ex        # KorE types → @spec + guards
│   │   │   └── actor.ex        # actor → GenServer
│   │   ├── prelude.ex          # prelude mapping table (§8)
│   │   └── errors.ex           # diagnostics with line/col, source excerpt
│   └── kore.ex                 # public compile API
├── priv/
│   └── templates/              # `kore new` project template
├── test/
│   ├── golden/                 # .kore → expected .ex golden tests
│   │   ├── cases/*.kore
│   │   └── cases/*.expected.ex
│   ├── runtime/                # compile & execute end-to-end tests
│   └── *_test.exs
└── docs/
    └── IMPLEMENTATION.md       # this file
```

---

## 3. Language specification

### 3.1 Lexical structure

- **Encoding**: UTF-8. Newlines are statement separators (semicolons optional,
  accepted, discouraged).
- **Comments**: `// line` and `/* block */` (nesting not required).
- **Identifiers**: `[a-zA-Z_][a-zA-Z0-9_]*`. Module/type names are
  `UpperCamelCase`; functions/values `lowerCamelCase` (convention, warn only).
- **Keywords**:
  `module fun val var data sealed when is if else return import actor spawn
  receive true false null in`
- **Literals**:
  - Int: `42`, `1_000_000` → Elixir integer
  - Double: `3.14` → Elixir float
  - String: `"text"` with interpolation `"Hello, $name"` and
    `"sum: ${a + b}"` → Elixir `"Hello, #{name}"`
  - Boolean: `true`, `false`
  - Null: `null` → `nil`
  - Atom: `:ok`, `:error` (exposed for interop; used by Result mapping)
- **Operators** (precedence high→low):
  `. ?. !!` · unary `- !` · `* / %` · `+ -` · `..` · `< > <= >=` · `== !=` ·
  `&&` · `||` · `?:` (elvis) · `=` (assignment/rebind)

### 3.2 Grammar (EBNF)

```ebnf
file          = { import } , module ;
import        = "import" , "elixir" , "." , dottedName ;
module        = "module" , TypeName , "{" , { declaration } , "}" ;
declaration   = funDecl | dataDecl | sealedDecl | actorDecl | valDecl ;

funDecl       = "fun" , name , "(" , [ params ] , ")" ,
                [ ":" , type ] , ( block | "=" , expr ) ;
params        = param , { "," , param } ;
param         = name , ":" , type , [ "=" , expr ] ;      (* default value *)

dataDecl      = "data" , TypeName , "(" , dataFields , ")" ;
dataFields    = dataField , { "," , dataField } ;
dataField     = "val" , name , ":" , type , [ "=" , expr ] ;

sealedDecl    = "sealed" , TypeName , "{" , { dataDecl } , "}" ;

actorDecl     = "actor" , TypeName , "(" , actorFields , ")" ,
                "{" , { funDecl } , "}" ;
actorFields   = actorField , { "," , actorField } ;
actorField    = ("val" | "var") , name , ":" , type , [ "=" , expr ] ;

valDecl       = ("val" | "var") , name , [ ":" , type ] , "=" , expr ;

block         = "{" , { statement } , "}" ;
statement     = valDecl | assignment | expr | returnStmt ;
assignment    = name , "=" , expr ;                        (* var rebind *)
returnStmt    = "return" , [ expr ] ;

expr          = ifExpr | whenExpr | lambda | receiveExpr
              | binaryExpr ;
ifExpr        = "if" , "(" , expr , ")" , (block|expr) ,
                [ "else" , (block|expr|ifExpr) ] ;
whenExpr      = "when" , "(" , expr , ")" , "{" , { whenBranch } , "}" ;
whenBranch    = whenCond , "->" , (block | expr) ;
whenCond      = "is" , TypeName , [ "(" , bindList , ")" ]  (* destructuring *)
              | expr , { "," , expr }                       (* value match  *)
              | "else" ;
bindList      = ("val" , name) , { "," , "val" , name } ;
lambda        = "{" , [ lambdaParams , "->" ] , { statement } , "}" ;
lambdaParams  = name { "," , name } ;                      (* or implicit it *)
receiveExpr   = "receive" , "{" , { whenBranch } , "}" ;

type          = TypeName , [ "<" , type , { "," , type } , ">" ] , [ "?" ] ;
```

Call syntax: `expr.method(args)`, `expr.method { lambda }` (trailing lambda,
as in Kotlin), `Function(args)`, `TypeName(args)` (constructor).

### 3.3 Types and their Elixir mapping

| KorE type       | Elixir typespec        | Runtime guard          |
|-----------------|------------------------|------------------------|
| `Int`           | `integer()`            | `is_integer/1`         |
| `Double`        | `float()`              | `is_float/1`           |
| `Boolean`       | `boolean()`            | `is_boolean/1`         |
| `String`        | `String.t()`           | `is_binary/1`          |
| `Atom`          | `atom()`               | `is_atom/1`            |
| `Unit`          | `:ok`                  | —                      |
| `Any`           | `term()`               | —                      |
| `List<T>`       | `[t()]`                | `is_list/1`            |
| `Map<K, V>`     | `%{optional(k) => v}`  | `is_map/1`             |
| `Pair<A, B>`    | `{a(), b()}`           | `is_tuple/1`           |
| `T?`            | `t() \| nil`           | guard on t, or nil     |
| `Result<T, E>`  | `{:ok, t()} \| {:error, e()}` | —               |
| `data Foo(...)` | `%Foo{}` struct        | `is_struct(x, Foo)`    |
| `(A) -> B`      | `(a() -> b())`         | `is_function/2`        |
| `Pid`           | `pid()`                | `is_pid/1`             |

`Unit` functions return `:ok` in generated Elixir.

---

## 4. Construct-by-construct mapping (KorE → Elixir)

### 4.1 Modules

```kotlin
module UserService {
    fun create(name: String): User = User(name, 0)
}
```
```elixir
defmodule Kore.UserService do
  @spec create(String.t()) :: Kore.User.t()
  def create(name) when is_binary(name) do
    %Kore.User{name: name, age: 0}
  end
end
```

- All generated modules are namespaced under `Kore.` (configurable later via
  `kore.toml`; hardcode `Kore.` in MVP).
- One `module` per file required in MVP. File name must match module name in
  snake_case (`user_service.kore` → `module UserService`); mismatch is a
  compile error.

### 4.2 Functions

```kotlin
fun greet(name: String): String {
    return "Hello, $name"
}
fun add(a: Int, b: Int): Int = a + b
fun log(msg: String) { println(msg) }          // Unit return
fun scale(x: Int, factor: Int = 2): Int = x * factor   // default param
```
```elixir
@spec greet(String.t()) :: String.t()
def greet(name) when is_binary(name) do
  "Hello, #{name}"
end

@spec add(integer(), integer()) :: integer()
def add(a, b) when is_integer(a) and is_integer(b), do: a + b

@spec log(String.t()) :: :ok
def log(msg) when is_binary(msg) do
  IO.puts(msg)
  :ok
end

@spec scale(integer(), integer()) :: integer()
def scale(x, factor \\ 2) when is_integer(x) and is_integer(factor),
  do: x * factor
```

Rules:
- Guards are emitted on **public function heads only**, and only for types
  with a cheap guard (see table §3.3). No guards inside lambdas or
  generated internal clauses.
- `return expr` in tail position compiles to the expression itself.
  `return` in non-tail position: MVP restriction — **compile error**
  ("early return not supported in v0.1"); revisit later via case rewriting.
- Missing return type = `Unit`.

### 4.3 val / var

```kotlin
val name: String = "diego"
var count = 0
count = count + 1
```
```elixir
name = "diego"
count = 0
count = count + 1
```

- `val` re-assignment → compile error.
- `var` re-assignment → plain Elixir rebinding.
- `var` rebind inside `if`/`when` blocks is threaded through (see §7.4).
- `var` rebind inside a lambda/closure → compile error:
  `"cannot rebind 'x' inside a lambda: BEAM closures capture values, not variables"`.

### 4.4 data (records)

```kotlin
data User(val name: String, val age: Int = 0)
```
```elixir
defmodule Kore.User do
  @enforce_keys [:name]
  defstruct name: nil, age: 0

  @type t :: %__MODULE__{name: String.t(), age: integer()}

  @spec new(String.t(), integer()) :: t()
  def new(name, age \\ 0), do: %__MODULE__{name: name, age: age}
end
```

Usage:

| KorE                          | Elixir                           |
|-------------------------------|----------------------------------|
| `User("diego", 30)`           | `Kore.User.new("diego", 30)`     |
| `u.name`                      | `u.name`                         |
| `u.copy(age = 31)`            | `%{u \| age: 31}`                |
| `val (n, a) = pair`           | `{n, a} = pair`                  |

- `data` declarations may appear at top level of a module; each compiles to a
  **nested-named module** (`Kore.<Module>.<Data>` if declared inside a module,
  `Kore.<Data>` if it is the file's only declaration). MVP: generate as
  separate `defmodule` in the same .ex file.
- Fields are `val`-only in `data` (no `var` fields).

### 4.5 sealed (sum types)

```kotlin
sealed Shape {
    data Circle(val r: Double)
    data Rect(val w: Double, val h: Double)
}
```
```elixir
defmodule Kore.Shape do
  @type t :: Kore.Shape.Circle.t() | Kore.Shape.Rect.t()
end

defmodule Kore.Shape.Circle do
  @enforce_keys [:r]
  defstruct [:r]
  @type t :: %__MODULE__{r: float()}
  def new(r), do: %__MODULE__{r: r}
end

defmodule Kore.Shape.Rect do
  @enforce_keys [:w, :h]
  defstruct [:w, :h]
  @type t :: %__MODULE__{w: float(), h: float()}
  def new(w, h), do: %__MODULE__{w: w, h: h}
end
```

The compiler records variant lists for exhaustiveness checking (§7.5).

### 4.6 when (pattern matching)

```kotlin
fun area(s: Shape): Double = when (s) {
    is Circle(val r) -> 3.14 * r * r
    is Rect(val w, val h) -> w * h
}

fun describe(n: Int): String = when (n) {
    0 -> "zero"
    1, 2 -> "small"
    else -> "big"
}
```
```elixir
@spec area(Kore.Shape.t()) :: float()
def area(s) do
  case s do
    %Kore.Shape.Circle{r: r} -> 3.14 * r * r
    %Kore.Shape.Rect{w: w, h: h} -> w * h
  end
end

@spec describe(integer()) :: String.t()
def describe(n) when is_integer(n) do
  case n do
    0 -> "zero"
    x when x in [1, 2] -> "small"
    _ -> "big"
  end
end
```

- `is Variant(val a, val b)` destructures positionally against the declared
  field order.
- `is Variant` without parens matches without binding.
- `when` over a `sealed`-typed subject without `else` must cover all variants
  (§7.5); with `else` it's always allowed.
- Value branches with multiple values compile to `x when x in [...]`.

### 4.7 if / else

`if` is an expression:

```kotlin
val label = if (n > 0) "pos" else "non-pos"
```
```elixir
label = if n > 0, do: "pos", else: "non-pos"
```

Block form generates `if ... do ... else ... end`.

### 4.8 Nullability

```kotlin
fun find(id: Int): User? = ...
val name = find(1)?.name ?: "unknown"
val forced = find(1)!!.name
```
```elixir
name =
  case find(1) do
    nil -> "unknown"
    kore_tmp1 ->
      case kore_tmp1.name do
        nil -> "unknown"
        kore_tmp2 -> kore_tmp2
      end
  end

# !! :
forced =
  case find(1) do
    nil -> raise Kore.NullError, "expression was null"
    kore_tmp -> kore_tmp.name
  end
```

Simplification: `?.` chains compile to nested `case`; when an elvis default
exists it becomes the `nil` branch, otherwise the `nil` branch yields `nil`.
Compiler-generated temporaries use the `kore_tmp<N>` prefix.

### 4.9 Result

`Result<T, E>` is a built-in sealed type mapped to Elixir tagged tuples
(NOT structs — for seamless interop):

```kotlin
fun parse(s: String): Result<Int, String> =
    if (s == "42") Ok(42) else Error("bad input")

fun use() {
    when (parse(input)) {
        is Ok(val v) -> println("got $v")
        is Error(val reason) -> println("failed: $reason")
    }
}
```
```elixir
@spec parse(String.t()) :: {:ok, integer()} | {:error, String.t()}
def parse(s) when is_binary(s) do
  if s == "42", do: {:ok, 42}, else: {:error, "bad input"}
end

def use() do
  case parse(input) do
    {:ok, v} -> IO.puts("got #{v}")
    {:error, reason} -> IO.puts("failed: #{reason}")
  end
  :ok
end
```

`Ok(x)` → `{:ok, x}`; `Error(e)` → `{:error, e}`; matching `is Ok(val v)` →
`{:ok, v}`. This makes every Elixir function returning ok/error tuples
directly consumable as `Result`.

### 4.10 Lambdas

```kotlin
val doubled = list.map { it * 2 }
val summed  = list.fold(0) { acc, x -> acc + x }
```
```elixir
doubled = Enum.map(list, fn it -> it * 2 end)
summed = Enum.reduce(list, 0, fn x, acc -> acc + x end)
```

- Single implicit parameter is `it`.
- Trailing-lambda call syntax supported: `f(a) { ... }` ≡ `f(a, { ... })`.
- Note `fold`'s argument order flip in `Enum.reduce` (acc last in Elixir's fn)
  — handled by the prelude mapping table (§8).

### 4.11 Collections

| KorE                         | Elixir                        |
|------------------------------|-------------------------------|
| `listOf(1, 2, 3)`            | `[1, 2, 3]`                   |
| `mapOf("a" to 1)`            | `%{"a" => 1}`                 |
| `Pair(a, b)` / `a to b`      | `{a, b}`                      |
| `list[0]`                    | `Enum.at(list, 0)`            |
| `map["a"]`                   | `Map.get(map, "a")`           |
| `x in list`                  | `x in list`                   |
| `1..10`                      | `1..10`                       |
| `for (x in list) { ... }`    | `Enum.each(list, fn x -> ... end)` |

### 4.12 Concurrency — primitives

```kotlin
fun worker() {
    receive {
        is Pair(val from: Pid, val msg: String) -> {
            from.send("echo: $msg")
        }
    }
}

fun main() {
    val pid = spawn { worker() }
    pid.send(Pair(self(), "hi"))
    receive {
        is String -> println(it)
    }
}
```
```elixir
def worker() do
  receive do
    {from, msg} when is_pid(from) and is_binary(msg) ->
      send(from, "echo: #{msg}")
      :ok
  end
  :ok
end

def main() do
  pid = spawn(fn -> worker() end)
  send(pid, {self(), "hi"})
  receive do
    it when is_binary(it) -> IO.puts(it)
  end
  :ok
end
```

- `spawn { ... }` → `spawn(fn -> ... end)` (returns `Pid`).
- `pid.send(x)` → `send(pid, x)`.
- `self()` → `self()`.
- `receive { branches }` uses `when`-branch syntax; `is Type` on primitive
  types compiles to a guard, on `data` types to a struct pattern, and the
  matched value binds to `it` when no destructuring is given.

### 4.13 Concurrency — actor

```kotlin
actor Counter(var count: Int = 0) {
    fun increment() { count += 1 }           // Unit → cast (async)
    fun add(n: Int) { count += n }           // Unit → cast
    fun get(): Int = count                   // value → call (sync)
}
```

Usage:

```kotlin
val c = Counter.start()          // or Counter.start(10)
c.increment()
c.add(5)
val n = c.get()
```

Generated:

```elixir
defmodule Kore.Counter do
  use GenServer

  # -- client API --
  def start(count \\ 0) do
    {:ok, pid} = GenServer.start_link(__MODULE__, %{count: count})
    pid
  end

  def increment(pid), do: GenServer.cast(pid, :increment)
  def add(pid, n), do: GenServer.cast(pid, {:add, n})
  def get(pid), do: GenServer.call(pid, :get)

  # -- server callbacks --
  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast(:increment, state) do
    count = state.count
    count = count + 1
    {:noreply, %{state | count: count}}
  end

  def handle_cast({:add, n}, state) do
    count = state.count
    count = count + n
    {:noreply, %{state | count: count}}
  end

  @impl true
  def handle_call(:get, _from, state) do
    count = state.count
    {:reply, count, state}
  end
end
```

Actor rules:
- Constructor params become the state map. `var` fields may be rebound in
  methods; `val` fields may not.
- Method returning `Unit` → `handle_cast` (fire-and-forget).
- Method with a return type → `handle_call` (synchronous).
- Method bodies read fields as locals (compiler prologue destructures state)
  and write back any `var` rebinding into the new state (epilogue).
- On the caller side, `c.method(args)` where `c: Counter` dispatches to the
  generated client function `Kore.Counter.method(c, args)`. Actor instances
  are pids; the KorE type of `Counter.start()` is `Counter` (nominal wrapper
  over `Pid` in the type table).
- No `handle_info`, supervision, or named actors in MVP.

### 4.14 Interop imports

```kotlin
import elixir.Ecto.Repo

fun fetchAll(): List<Any> = Repo.all(userQuery)
```
```elixir
def fetch_all() do
  Ecto.Repo.all(user_query)
end
```

- `import elixir.X.Y` makes `Y` callable; calls pass through verbatim
  (aliased in the generated module).
- Called functions are untyped from KorE's perspective (`Any` in / `Any` out);
  emit no guards for them.
- Erlang modules: `import elixir.:erlang` allowed in grammar as
  `import elixir.` + atom; MVP may defer this.

---

## 5. The prelude (§8 of design decisions)

The prelude is a compile-time mapping table (`lib/kore/prelude.ex`), not a
runtime library, wherever possible: `list.map { ... }` is rewritten during
codegen to `Enum.map(list, fn ...)`. Only helpers with no direct Elixir
equivalent generate a small runtime support module `Kore.Runtime` (e.g.
`listOf` needs nothing; keep `Kore.Runtime` for future use like `NullError`).

MVP prelude functions:

| KorE call                    | Elixir target                                  |
|------------------------------|------------------------------------------------|
| `println(x)`                 | `IO.puts(x)` (non-strings: `IO.inspect(x)`)    |
| `print(x)`                   | `IO.write(x)`                                  |
| `readLine()`                 | `IO.gets("") \|> String.trim_trailing()`       |
| `list.map { }`               | `Enum.map(list, fn)`                           |
| `list.filter { }`            | `Enum.filter(list, fn)`                        |
| `list.forEach { }`           | `Enum.each(list, fn)`                          |
| `list.fold(init) { a, x -> }`| `Enum.reduce(list, init, fn x, a -> end)`      |
| `list.size`                  | `length(list)`                                 |
| `list.first()` / `.last()`   | `List.first(list)` / `List.last(list)`        |
| `list.isEmpty()`             | `Enum.empty?(list)`                            |
| `list.contains(x)`           | `x in list`                                    |
| `list.reversed()`            | `Enum.reverse(list)`                           |
| `list.sorted()`              | `Enum.sort(list)`                              |
| `list.joinToString(sep)`     | `Enum.join(list, sep)`                         |
| `s.length`                   | `String.length(s)`                             |
| `s.uppercase()`/`lowercase()`| `String.upcase(s)` / `String.downcase(s)`      |
| `s.trim()`                   | `String.trim(s)`                               |
| `s.split(sep)`               | `String.split(s, sep)`                         |
| `s.startsWith(p)`            | `String.starts_with?(s, p)`                    |
| `s.toInt()`                  | `String.to_integer(s)`                         |
| `x.toString()`               | `to_string(x)`                                 |
| `map.get(k)` / `map[k]`      | `Map.get(map, k)`                              |
| `map.put(k, v)`              | `Map.put(map, k, v)` (returns new map)         |
| `map.keys` / `map.values`    | `Map.keys(map)` / `Map.values(map)`            |

Dispatch rule: method-call syntax `recv.name(args)` is looked up in the
prelude table first (keyed by name + arity; receiver type used when known,
name+arity is enough for MVP). If not found and `recv` is an actor type,
dispatch as actor call. If not found and name matches an imported
`elixir.` module member, pass through. Otherwise: compile error
`unknown function`.

Name mangling: KorE `lowerCamelCase` function names compile to Elixir
`snake_case` (`fetchAll` → `fetch_all`). Applied consistently to definitions
and call sites.

---

## 6. Compiler pipeline detail

### 6.1 Lexer (`lexer.ex`)

- Hand-written scanner producing `{type, value, line, col}` tuples.
- Handles nested string interpolation by emitting
  `:string_start / :interp_start / … / :interp_end / :string_end` token runs.
- Newline tokens emitted; parser treats them as statement terminators
  (Kotlin-style: a newline ends a statement unless the expression is clearly
  incomplete — trailing binary operator, open paren/brace, `.` etc.).

### 6.2 Parser (`parser.ex`)

- Recursive descent with Pratt-style expression parsing (precedence table
  §3.1).
- Produces AST structs defined in `ast.ex`. Every node carries
  `meta: %{line:, col:}` for diagnostics.

Suggested AST nodes:

```
Module, Import, FunDecl, Param, DataDecl, SealedDecl, ActorDecl,
ValDecl, Assign, Block, If, When, WhenBranch, PatternIs, PatternValue,
Lambda, Call, MethodCall, FieldAccess, SafeAccess, Elvis, NotNull,
BinOp, UnaryOp, Literal, StringInterp, VarRef, ConstructorCall,
Spawn, Receive, Return, For, Range, TupleLit, ListLit, MapLit
```

### 6.3 Semantic passes (in order)

1. **Declaration collection**: index modules, functions (name/arity), data
   types + field lists, sealed variant sets, actors + method kinds
   (cast/call).
2. **Name resolution & scoping** (`scopes.ex`): resolve every `VarRef`;
   classify `val`/`var`; error on: undefined name, `val` reassignment,
   duplicate declaration in same scope.
3. **Closure check** (`closures.ex`): walk lambdas; any `Assign` to an outer
   `var` → error.
4. **Var threading** (`var_threading.ex`) — see §7.4 below.
5. **Exhaustiveness** (`exhaustive.ex`): for `when` whose subject's static
   type is a sealed type, require all variants or `else`.
6. **Minimal type checks** (`typecheck.ex`):
   - literal/annotation mismatch (`val x: Int = "hi"`),
   - call arity vs. declaration,
   - constructor field count,
   - condition of `if`/guards is `Boolean` when statically known.
   Everything else falls through to the Elixir compiler / Dialyzer.

### 6.4 `var` threading (decision §7A)

Blocks (`if`/`when` used as statements) that rebind outer `var`s are
rewritten so the new value escapes the block, since Elixir scoping discards
inner bindings:

Input:

```kotlin
var x = 1
if (cond) {
    x = 2
    log(x)
}
println(x)   // must print 2
```

Rewrite algorithm:
1. For each `if`/`when` **statement** (not expression position), compute the
   set `V` of outer `var`s assigned in any branch.
2. If `V` is empty, no rewrite.
3. If `V = {x}`: make the block evaluate to the final value of `x` in each
   branch (append `x` as last expression; for absent else branch, synthesize
   `else -> x`), and bind: `x = if ... end`.
4. If `|V| > 1`: evaluate to a tuple `{x, y}` per branch and destructure:
   `{x, y} = if ... end`.

Generated Elixir for the example:

```elixir
x = 1
x =
  if cond do
    x = 2
    log(x)
    x
  else
    x
  end
IO.puts(x)
```

Nested blocks are handled by applying the rewrite bottom-up. Loops other than
`for`-over-collections don't exist in MVP (`while` deferred), so no loop
threading needed. `var` rebinding inside `for` bodies → compile error in MVP
("use fold instead"), because `Enum.each` can't thread state.

### 6.5 Codegen (`codegen/elixir.ex`)

- Emit Elixir **source text** (not AST) with a simple indenting pretty
  printer. Deterministic output (goldens depend on it).
- Every generated file starts with a header comment:
  `# Generated by KorE vX — do not edit. Source: lib/user_service.kore`
- One `.kore` file → one `.ex` file at
  `_build/kore_gen/lib/<snake_name>.ex` (may contain multiple `defmodule`s
  for data/sealed variants).
- `@spec` emission (`codegen/specs.ex`) per table §3.3; guard emission on
  public heads per §4.2.

### 6.6 Errors (`errors.ex`)

All compile errors report: file, line:col, message, 1-line source excerpt
with caret. Errors are collected per-file (report as many as possible, don't
stop at first). Exit code 1 on any error.

---

## 7. CLI (`cli.ex`, escript)

```
kore new <name>      # scaffold a project
kore build           # compile .kore → elixir → beam
kore run [module]    # build + run Kore.Main.main() (or given module's main)
kore version
```

### `kore new myapp` produces

```
myapp/
├── kore.exs            # minimal project config (name, version)
├── lib/
│   └── main.kore       # module Main { fun main() { println("Hello, KorE!") } }
└── .gitignore          # _build/
```

### `kore build` steps

1. Read `kore.exs` config.
2. Compile all `lib/**/*.kore` through the pipeline into
   `_build/kore_gen/lib/*.ex`.
3. Synthesize `_build/kore_gen/mix.exs` (app name from config).
4. Shell out: `cd _build/kore_gen && mix compile` (surface Elixir errors,
   mapped back to the header-comment source file at minimum; precise line
   mapping is out of MVP scope).

### `kore run`

`kore build`, then `cd _build/kore_gen && mix run -e "Kore.Main.main()"`.

Build the CLI as an escript (`mix escript.build`), binary name `kore`.
Requirement: Elixir/OTP installed on the host (document in README).

---

## 8. Testing strategy

1. **Unit tests**: lexer (token streams incl. interpolation), parser
   (AST shapes), each semantic pass (positive + error cases).
2. **Golden tests** (`test/golden/`): each case is `name.kore` +
   `name.expected.ex`; test compiles and string-compares. Add a
   `KORE_UPDATE_GOLDEN=1` env flag to regenerate.
   Minimum golden cases: module+fun, expression body, defaults, val/var,
   var-threading (if/when, multi-var), data, copy, sealed+when exhaustive,
   when values/else, nullability chain, elvis, `!!`, Result, lambdas
   (implicit it, trailing, fold), string interpolation, collections, for,
   spawn/receive/send, actor (cast+call+val/var state), import elixir,
   name mangling.
3. **Runtime tests** (`test/runtime/`): compile a `.kore` snippet end-to-end,
   execute the generated module inside the test VM
   (`Code.compile_string/1` on generated source), assert on results/output.
   Cover: arithmetic/strings, var threading correctness, Result matching,
   actor Counter behaviour, prelude functions, null-safety operators.
4. **Error tests**: val reassignment, var-in-lambda, non-exhaustive when,
   arity mismatch, type literal mismatch, unknown function, file/module name
   mismatch, early return.

---

## 9. Implementation phases (ordered)

| Phase | Scope | Exit criterion |
|-------|-------|----------------|
| 1 | Mix project, AST, lexer, parser | parser unit tests green for full grammar |
| 2 | Scopes, closures check, minimal typecheck; codegen for module/fun/val/var/if/literals/interp/binops; specs+guards | first goldens green; `Hello KorE` runtime test |
| 3 | Prelude table + method dispatch + name mangling; collections; lambdas; for | prelude goldens + runtime tests |
| 4 | data, sealed, when (destructuring, exhaustiveness), Result, nullability ops | matching goldens + runtime tests |
| 5 | var threading rewrite | threading goldens + runtime correctness tests |
| 6 | spawn/send/receive; actor → GenServer | actor runtime tests |
| 7 | CLI escript: new/build/run; project template; README | `kore new demo && kore run` works end-to-end |

Each phase must land with its tests. Do not start a phase before the previous
one's tests pass.

---

## 10. Explicitly out of scope for v0.1

- `while` loops, early `return`, `break`/`continue`
- Generics beyond built-in `List/Map/Pair/Result` (no user-defined generics)
- Interfaces/traits, extension functions, operator overloading
- Supervision trees, named/registered actors, `handle_info`
- Type inference beyond literals; full type checking (delegated to
  Elixir compiler + Dialyzer)
- Source maps / precise error mapping from Elixir errors back to .kore lines
- Configurable root namespace (fixed `Kore.`)
- Macros, string `"""` raw literals, char type
- Mix dependency management from `kore.exs` (users can edit generated mix.exs
  later; proper support in v0.2)

---

## 11. Worked end-to-end example

`lib/bank.kore`:

```kotlin
module Bank {
    data Account(val owner: String, val balance: Int = 0)

    sealed TxResult {
        data Approved(val newBalance: Int)
        data Denied(val reason: String)
    }

    fun withdraw(acc: Account, amount: Int): TxResult =
        if (amount <= acc.balance) Approved(acc.balance - amount)
        else Denied("insufficient funds")

    fun report(acc: Account, amount: Int): String {
        var msg = "pending"
        when (withdraw(acc, amount)) {
            is Approved(val b) -> { msg = "ok, new balance $b" }
            is Denied(val r) -> { msg = "denied: $r" }
        }
        return msg
    }
}
```

Generated `_build/kore_gen/lib/bank.ex`:

```elixir
# Generated by KorE v0.1 — do not edit. Source: lib/bank.kore

defmodule Kore.Bank.Account do
  @enforce_keys [:owner]
  defstruct owner: nil, balance: 0
  @type t :: %__MODULE__{owner: String.t(), balance: integer()}
  def new(owner, balance \\ 0), do: %__MODULE__{owner: owner, balance: balance}
end

defmodule Kore.Bank.TxResult do
  @type t :: Kore.Bank.TxResult.Approved.t() | Kore.Bank.TxResult.Denied.t()
end

defmodule Kore.Bank.TxResult.Approved do
  @enforce_keys [:new_balance]
  defstruct [:new_balance]
  @type t :: %__MODULE__{new_balance: integer()}
  def new(new_balance), do: %__MODULE__{new_balance: new_balance}
end

defmodule Kore.Bank.TxResult.Denied do
  @enforce_keys [:reason]
  defstruct [:reason]
  @type t :: %__MODULE__{reason: String.t()}
  def new(reason), do: %__MODULE__{reason: reason}
end

defmodule Kore.Bank do
  @spec withdraw(Kore.Bank.Account.t(), integer()) :: Kore.Bank.TxResult.t()
  def withdraw(acc, amount)
      when is_struct(acc, Kore.Bank.Account) and is_integer(amount) do
    if amount <= acc.balance do
      Kore.Bank.TxResult.Approved.new(acc.balance - amount)
    else
      Kore.Bank.TxResult.Denied.new("insufficient funds")
    end
  end

  @spec report(Kore.Bank.Account.t(), integer()) :: String.t()
  def report(acc, amount)
      when is_struct(acc, Kore.Bank.Account) and is_integer(amount) do
    msg = "pending"
    msg =
      case withdraw(acc, amount) do
        %Kore.Bank.TxResult.Approved{new_balance: b} ->
          msg = "ok, new balance #{b}"
          msg
        %Kore.Bank.TxResult.Denied{reason: r} ->
          msg = "denied: #{r}"
          msg
      end
    msg
  end
end
```

Note the field name mangling (`newBalance` → `new_balance`) and the
var-threading of `msg` through the `when` statement.
