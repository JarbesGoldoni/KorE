# KorE Language Reference (v0.1)

Single-source-of-truth specification for the KorE language. Everything in this
document reflects the implemented, verified compiler behaviour.

---

## 1. Grammar (EBNF)

### 1.1 Keywords (21)

```
module  fun  val  var  data  sealed  when  is  if  else  return
import  actor  spawn  receive  true  false  null  in  for  to
```

### 1.2 Operators

**Two-character tokens:**

| Token | Name |
|-------|------|
| `?.` | safe_dot |
| `!!` | not_null |
| `..` | range |
| `<=` | less_eq |
| `>=` | greater_eq |
| `==` | eq_eq |
| `!=` | not_eq |
| `&&` | and_and |
| `||` | or_or |
| `?:` | elvis |
| `+=` | plus_eq (desugared by parser to `x = x + expr`) |
| `-=` | minus_eq (desugared by parser to `x = x - expr`) |
| `->` | arrow |

**Single-character tokens:**

```
.  -  !  *  /  %  +  <  >  =  (  )  {  }  ,  :  ;  ?
```

**Precedence (high to low):**

1. `. ?. !!` (postfix/access)
2. Unary `- !`
3. `* / %`
4. `+ -`
5. `..` (range)
6. `< > <= >=`
7. `== !=`
8. `&&`
9. `||`
10. `?:` (elvis)
11. `to` (pair constructor — keyword, behaves as infix)
12. `=` (assignment/rebind)

### 1.3 Complete Grammar

```ebnf
file          = { import } , module ;
import        = "import" , "elixir" , "." , dottedName ;
dottedName    = TypeName , { "." , TypeName } ;
module        = "module" , TypeName , "{" , { declaration } , "}" ;
declaration   = funDecl | dataDecl | sealedDecl | actorDecl | valDecl ;

funDecl       = "fun" , name , "(" , [ params ] , ")" ,
                [ ":" , type ] , ( block | "=" , expr ) ;
params        = param , { "," , param } ;
param         = name , ":" , type , [ "=" , expr ] ;

dataDecl      = "data" , TypeName , "(" , dataFields , ")" ;
dataFields    = dataField , { "," , dataField } ;
dataField     = "val" , name , ":" , type , [ "=" , expr ] ;

sealedDecl    = "sealed" , TypeName , "{" , { dataDecl } , "}" ;

actorDecl     = "actor" , TypeName , "(" , actorFields , ")" ,
                "{" , { funDecl } , "}" ;
actorFields   = actorField , { "," , actorField } ;
actorField    = ( "val" | "var" ) , name , ":" , type , [ "=" , expr ] ;

valDecl       = ( "val" | "var" ) , name , [ ":" , type ] , "=" , expr ;

block         = "{" , { statement } , "}" ;
statement     = valDecl | assignment | expr | returnStmt ;
assignment    = name , ( "=" | "+=" | "-=" ) , expr ;
returnStmt    = "return" , [ expr ] ;

expr          = ifExpr | whenExpr | forExpr | lambda | receiveExpr
              | spawnExpr | binaryExpr ;
ifExpr        = "if" , "(" , expr , ")" , ( block | expr ) ,
                [ "else" , ( block | expr | ifExpr ) ] ;
whenExpr      = "when" , "(" , expr , ")" , "{" , { whenBranch } , "}" ;
whenBranch    = whenCond , "->" , ( block | expr ) ;
whenCond      = "is" , TypeName , [ "(" , bindList , ")" ]
              | expr , { "," , expr }
              | "else" ;
bindList      = ( "val" , name ) , { "," , "val" , name } ;
forExpr       = "for" , "(" , name , "in" , expr , ")" , block ;
lambda        = "{" , [ lambdaParams , "->" ] , { statement } , "}" ;
lambdaParams  = name , { "," , name } ;
receiveExpr   = "receive" , "{" , { whenBranch } , "}" ;
spawnExpr     = "spawn" , block ;

type          = TypeName , [ "<" , type , { "," , type } , ">" ] , [ "?" ] ;

(* Call/access syntax — parsed via Pratt precedence *)
callExpr      = primary , { "." , name , [ "(" , argList , ")" ] , [ lambda ] }
              | primary , "?." , name , [ "(" , argList , ")" ]
              | primary , "!!" , "." , name
              | TypeName , "(" , argList , ")"
              | name , "(" , argList , ")" , [ lambda ]
              | expr , "." , "copy" , "(" , copyArgs , ")" ;
copyArgs      = name , "=" , expr , { "," , name , "=" , expr } ;
argList       = expr , { "," , expr } ;
```

### 1.4 Literals

| Literal | Syntax | Example |
|---------|--------|---------|
| Int | `[0-9][0-9_]*` | `42`, `1_000_000` |
| Double | `[0-9][0-9_]*\.[0-9][0-9_]*` | `3.14`, `1_000.50` |
| String | `"..."` with `$name` / `${expr}` interpolation | `"Hello, $name"` |
| Boolean | `true` / `false` | |
| Null | `null` | |
| Atom | `:[a-zA-Z_][a-zA-Z0-9_]*` | `:ok`, `:error` |

### 1.5 Comments

- Line comment: `// ...`
- Block comment: `/* ... */` (non-nesting)

---

## 2. Type System

| KorE Type | Elixir Typespec | Runtime Guard | Notes |
|-----------|-----------------|---------------|-------|
| `Int` | `integer()` | `is_integer/1` | |
| `Double` | `float()` | `is_float/1` | |
| `Boolean` | `boolean()` | `is_boolean/1` | |
| `String` | `String.t()` | `is_binary/1` | |
| `Atom` | `atom()` | `is_atom/1` | For interop |
| `Unit` | `:ok` | — | Functions with no return type |
| `Any` | `term()` | — | No guard emitted |
| `List<T>` | `[t()]` | `is_list/1` | |
| `Map<K, V>` | `%{optional(k) => v}` | `is_map/1` | |
| `Pair<A, B>` | `{a(), b()}` | `is_tuple/1` | |
| `T?` | `t() \| nil` | guard on t, or nil | Nullable |
| `Result<T, E>` | `{:ok, t()} \| {:error, e()}` | — | Built-in sealed; maps to tuples |
| `data Foo(...)` | `%Kore.Foo{}` struct | `is_struct(x, Kore.Foo)` | |
| `(A) -> B` | `(a() -> b())` | `is_function/2` | Lambda type |
| `Pid` | `pid()` | `is_pid/1` | |

**Type annotations** are optional on local variables (compiler infers from literal).
Required on function parameters. Return type optional (defaults to `Unit`).

**No user-defined generics.** Only the built-in parameterized types listed above.

---

## 3. Prelude Reference (Complete)

All built-in methods and functions with their full signatures.

### 3.1 Top-Level Functions

| KorE Signature | Elixir Output | Notes |
|----------------|---------------|-------|
| `println(x: Any): Unit` | `IO.puts(x)` | Non-strings go through `IO.inspect` |
| `print(x: Any): Unit` | `IO.write(x)` | No newline |
| `readLine(): String` | `IO.gets("") \|> String.trim_trailing()` | Reads one line from stdin |
| `self(): Pid` | `self()` | Current process PID |
| `listOf(varargs: T): List<T>` | `[a, b, ...]` | Literal list construction |
| `mapOf(varargs: Pair<K,V>): Map<K,V>` | `%{k => v, ...}` | Literal map construction |

### 3.2 List/Enum Methods

| KorE Signature | Elixir Output | Notes |
|----------------|---------------|-------|
| `list.map { (T) -> R }: List<R>` | `Enum.map(list, fn)` | |
| `list.filter { (T) -> Boolean }: List<T>` | `Enum.filter(list, fn)` | |
| `list.forEach { (T) -> Unit }: Unit` | `Enum.each(list, fn)` | |
| `list.fold(init: R) { (R, T) -> R }: R` | `Enum.reduce(list, init, fn x, acc -> end)` | Arg order flipped in Elixir fn |
| `list.first(): T?` | `List.first(list)` | Returns nil if empty |
| `list.last(): T?` | `List.last(list)` | Returns nil if empty |
| `list.isEmpty(): Boolean` | `Enum.empty?(list)` | |
| `list.contains(x: T): Boolean` | `x in list` | Rewritten to `in` operator |
| `list.reversed(): List<T>` | `Enum.reverse(list)` | |
| `list.sorted(): List<T>` | `Enum.sort(list)` | |
| `list.joinToString(sep: String): String` | `Enum.join(list, sep)` | |
| `list.size: Int` | `length(list)` | Property (no parens) |
| `list.plus(x: T): List<T>` | `list ++ [x]` | Append single element |
| `list.plusAll(other: List<T>): List<T>` | `list ++ other` | Concatenate lists |
| `list.take(n: Int): List<T>` | `Enum.take(list, n)` | |
| `list.drop(n: Int): List<T>` | `Enum.drop(list, n)` | |
| `list.sum(): Int` | `Enum.sum(list)` | Numeric lists only |
| `list.count { (T) -> Boolean }: Int` | `Enum.count(list, fn)` | |
| `list.any { (T) -> Boolean }: Boolean` | `Enum.any?(list, fn)` | |
| `list.all { (T) -> Boolean }: Boolean` | `Enum.all?(list, fn)` | |
| `list.flatMap { (T) -> List<R> }: List<R>` | `Enum.flat_map(list, fn)` | |
| `list.distinct(): List<T>` | `Enum.uniq(list)` | |

### 3.3 String Methods

| KorE Signature | Elixir Output | Notes |
|----------------|---------------|-------|
| `s.length: Int` | `String.length(s)` | Property (no parens) |
| `s.uppercase(): String` | `String.upcase(s)` | |
| `s.lowercase(): String` | `String.downcase(s)` | |
| `s.trim(): String` | `String.trim(s)` | |
| `s.split(sep: String): List<String>` | `String.split(s, sep)` | |
| `s.startsWith(prefix: String): Boolean` | `String.starts_with?(s, prefix)` | |
| `s.endsWith(suffix: String): Boolean` | `String.ends_with?(s, suffix)` | |
| `s.includes(sub: String): Boolean` | `String.contains?(s, sub)` | |
| `s.replace(pattern: String, replacement: String): String` | `String.replace(s, pattern, replacement)` | |
| `s.toInt(): Int` | `String.to_integer(s)` | Raises on invalid input |
| `s.toDouble(): Double` | `String.to_float(s)` | Raises on invalid input |
| `s.toString(): String` | `to_string(s)` | Identity for strings |

### 3.4 Map Methods

| KorE Signature | Elixir Output | Notes |
|----------------|---------------|-------|
| `map.get(key: K): V?` | `Map.get(map, key)` | Returns nil if missing |
| `map.put(key: K, value: V): Map<K,V>` | `Map.put(map, key, value)` | Returns new map |
| `map.remove(key: K): Map<K,V>` | `Map.delete(map, key)` | Returns new map |
| `map.containsKey(key: K): Boolean` | `Map.has_key?(map, key)` | |
| `map.keys: List<K>` | `Map.keys(map)` | Property (no parens) |
| `map.values: List<V>` | `Map.values(map)` | Property (no parens) |
| `map.mapSize: Int` | `map_size(map)` | Property (no parens) |

### 3.5 Process Methods

| KorE Signature | Elixir Output | Notes |
|----------------|---------------|-------|
| `pid.send(msg: Any): Any` | `send(pid, msg)` | Rewritten; returns the message |

### 3.6 Result Constructors

| KorE | Elixir Output | Notes |
|------|---------------|-------|
| `Ok(value)` | `{:ok, value}` | |
| `Error(reason)` | `{:error, reason}` | |

### 3.7 Dispatch Rules

1. Method-call `recv.name(args)` is looked up in prelude table first (by name + arity).
2. If not found and `recv` is an actor type → dispatch as actor call/cast.
3. If not found and name matches imported `elixir.` module → pass through.
4. Otherwise → compile error.

---

## 4. Name Mangling Algorithm

### 4.1 Function and Variable Names

All `lowerCamelCase` identifiers are converted to `snake_case` in generated Elixir.

**Algorithm (pseudocode):**

```
function to_snake_case(name):
    result = ""
    prev_was_upper = false
    for each char in name:
        if char is uppercase:
            lower = lowercase(char)
            if result is empty:
                result += lower
            else if prev_was_upper:
                result += lower        # consecutive uppercase grouped
            else:
                result += "_" + lower
            prev_was_upper = true
        else:
            result += char
            prev_was_upper = false
    return result
```

**Examples:**

| KorE | Elixir |
|------|--------|
| `getUserName` | `get_user_name` |
| `getHTTPStatus` | `get_httpstatus` |
| `firstName` | `first_name` |
| `toInt` | `to_int` |
| `isEmpty` | `is_empty` |
| `joinToString` | `join_to_string` |

Note: consecutive uppercase letters are grouped (no underscore between them).
`getHTTPStatus` becomes `get_httpstatus`, not `get_h_t_t_p_status`.

### 4.2 Module Names

Module names stay `UpperCamelCase`. No mangling applied. All generated modules
are namespaced under `Kore.`:

- `module UserService` → `defmodule Kore.UserService`
- `data User` inside `module Main` → `defmodule Kore.Main.User`

### 4.3 Field Names in Data Records

Data record field names follow the same `lowerCamelCase` → `snake_case` rule:

- `val newBalance: Int` → `new_balance` in the generated struct

---

## 5. Not Supported (v0.1)

These features are explicitly absent from the language. Using them produces a
compile error or is simply not parseable.

- **`while`, `break`, `continue`** — use recursion or `list.fold { }` for accumulation
- **Early `return`** — `return` only valid in tail position (last expression in function body); non-tail `return` is a compile error
- **User-defined generics** — only built-in `List<T>`, `Map<K,V>`, `Pair<A,B>`, `Result<T,E>`
- **Interfaces/traits** — no interface, trait, or abstract keyword
- **Extension functions** — cannot add methods to existing types
- **Operator overloading** — operators have fixed semantics
- **`try`/`catch`/`finally`** — use `Result` + pattern matching (let-it-crash philosophy)
- **`map[key]` bracket subscript** — use `map.get(key)` instead
- **`var` fields in `data` records** — only `val` fields allowed
- **`var` rebinding inside lambdas/closures** — compile error (BEAM closures capture values)
- **`var` rebinding inside `for` bodies** — compile error (use `fold` instead)
- **Multi-module files** — one `module` declaration per `.kore` file
- **Supervision trees / named actors / `handle_info`** — only anonymous actor spawning
- **Type inference beyond literals** — type annotations required on parameters; only literal types inferred for locals
- **Source maps** — no precise error mapping from Elixir errors back to `.kore` lines
- **Macros** — no macro system
- **Raw string literals** (`"""`) — not supported
- **Char type** — no dedicated character type

---

## 6. Error Catalog

All 22 compiler errors organized by the pass that produces them.

### 6.1 Lexer Errors (6)

| # | Message Pattern | Cause | Fix |
|---|----------------|-------|-----|
| L1 | `Unexpected end of input` | Source ends while inside a string or interpolation mode | Close the open string with `"` |
| L2 | `Invalid interpolation identifier` | `$` followed by a non-identifier character inside a string | Use `${expr}` for complex expressions or ensure valid identifier after `$` |
| L3 | `Unterminated block comment` | `/*` without matching `*/` | Add closing `*/` |
| L4 | `Invalid number` | Digit sequence that cannot be parsed as int or float | Fix numeric literal format |
| L5 | `Unterminated string` | String literal reaches end of input without closing `"` | Close the string with `"` |
| L6 | `Invalid character` | Character not part of any valid token | Remove or replace the invalid character |

### 6.2 Parser Errors (5)

| # | Message Pattern | Cause | Fix |
|---|----------------|-------|-----|
| P1 | `Expected <X>, got <Y>` | Parser expected a specific token type but found something else | Check syntax; add the expected token |
| P2 | `Unexpected <token> at module level; expected 'fun', 'val', 'var', 'data', 'sealed', or 'actor'` | Invalid declaration inside module body | Only use allowed declaration keywords at module level |
| P3 | `Expected block or = for function body` | `fun` declaration has neither a `{ }` body nor `= expr` | Add a block body or expression body to the function |
| P4 | `Cannot start an expression with <token>; expected a value, identifier, '(', 'if', 'when', 'for', or unary operator` | Expression parsing found an unexpected leading token | Ensure expression starts with a valid prefix |
| P5 | `Expected field or method name after '.', got <token>` | Dot access followed by something that isn't an identifier | Add a valid field or method name after `.` |

### 6.3 Scopes Errors (6)

| # | Message Pattern | Cause | Fix |
|---|----------------|-------|-----|
| S1 | `duplicate declaration '<name>' in same scope` | Two `val`/`var` declarations with the same name in one scope | Rename one of the declarations |
| S2 | `undefined variable '<name>'` (on assignment) | Assigning to a name that was never declared | Declare with `val` or `var` first |
| S3 | `cannot reassign 'val' variable '<name>'` | Attempting `name = ...` on a `val` binding | Change to `var` if rebinding is needed |
| S4 | `undefined variable '<name>'` (on reference) | Using a name that was never declared or imported | Declare the variable, import the module, or fix the typo |
| S5 | `file name '<file>' does not match module name '<Module>' (expected '<expected>.kore')` | File name and module name don't correspond | Rename the file to match the module in snake_case |
| S6 | `early return not supported; restructure using if/when expressions or move the return to the last position in the function body` | `return` appears in a non-tail position | Move logic into `if`/`when` expressions or place `return` at end |

### 6.4 Closures Error (1)

| # | Message Pattern | Cause | Fix |
|---|----------------|-------|-----|
| C1 | `cannot rebind '<name>' inside a lambda: BEAM closures capture values, not variables` | Assigning to an outer `var` from within a lambda | Use `fold` or restructure to avoid mutating captures |

### 6.5 Exhaustiveness Error (1)

| # | Message Pattern | Cause | Fix |
|---|----------------|-------|-----|
| E1 | `non-exhaustive 'when' for sealed type '<Type>': missing variants [<list>]. Add missing branches or an 'else' branch.` | `when` over a sealed type doesn't cover all variants and has no `else` | Add the missing variant branches or add `else ->` |

### 6.6 Typecheck Errors (3)

| # | Message Pattern | Cause | Fix |
|---|----------------|-------|-----|
| T1 | `type mismatch: expected '<Type>', got <literal_type> literal` | Annotated type contradicts the assigned literal | Change the annotation or the literal |
| T2 | `function '<name>' expects <min>..<max> arguments, got <given>` | Function called with wrong number of arguments | Match the declared parameter count (accounting for defaults) |
| T3 | `constructor '<name>' expects <min>..<max> fields, got <given>` | Data constructor called with wrong number of fields | Match the declared field count (accounting for defaults) |

---

## 7. File Naming Rules

### 7.1 Convention

- Every `.kore` file must contain exactly one `module` declaration.
- File name: `snake_case.kore`
- Module name: `UpperCamelCase`
- The file name must be the snake_case conversion of the module name.

### 7.2 Examples

| Module Name | File Name |
|-------------|-----------|
| `Main` | `main.kore` |
| `UserService` | `user_service.kore` |
| `HTTPClient` | `httpclient.kore` |
| `CounterApp` | `counter_app.kore` |

### 7.3 Violation

Mismatch produces Scopes error S5:
```
lib/my_file.kore:1:1: error: file name 'my_file.kore' does not match module name 'UserService' (expected 'user_service.kore')
```

### 7.4 Generated Output Path

Each `.kore` file produces one `.ex` file at:
```
_build/kore_gen/lib/<snake_name>.ex
```

The `.ex` file may contain multiple `defmodule`s (for nested `data`/`sealed` types).
All generated modules are namespaced under `Kore.`.
