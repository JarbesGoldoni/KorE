# KorE Restructuring — Validation Report

This document describes all changes made during the KorE repo restructuring,
how to test each change, and what to look for when validating correctness.

---

## Prerequisites

- Elixir >= 1.15 and Erlang/OTP >= 25 installed
- From the KorE repo root, run: `mix deps.get && mix compile`
- If compile fails, that's the first thing to fix before proceeding

---

## Changes Summary

### Wave 1: Compiler Fixes (code changes)

#### 1.1 — `+=` / `-=` operator support (parser desugar)

**Files changed:** `lib/kore/parser.ex` (lines ~455-477)

**What it does:** The lexer already tokenized `+=` and `-=` but the parser never consumed them. Now, `x += expr` desugars to `Assign(x, BinOp(:plus, VarRef(x), expr))`.

**How to test:**
```bash
# Create a test file
cat > /tmp/test_compound.kore << 'EOF'
module Main {
    fun main() {
        var x = 10
        x += 5
        x -= 3
        println(x.toString())
    }
}
EOF

# Compile through the pipeline (should produce valid Elixir)
mix run -e '
source = File.read!("/tmp/test_compound.kore")
case Kore.compile(source, file: "/tmp/test_compound.kore") do
  {:ok, code} -> IO.puts(code)
  {:error, e} -> IO.puts(Kore.Errors.format_all(e))
end
'
```

**Expected:** Output contains `x = x + 5` and `x = x - 3` (desugared, no `+=` in output).

**Also verify in actors:**
```bash
cat > /tmp/test_actor_compound.kore << 'EOF'
module Main {
    actor Counter(var count: Int = 0) {
        fun increment() { count += 1 }
        fun get(): Int = count
    }
    fun main() {
        val c = Counter.start()
        c.increment()
        println(c.get().toString())
    }
}
EOF
```

---

#### 1.2 — New prelude methods

**File changed:** `lib/kore/prelude.ex`

**New entries (16 methods):**

| Method | Category | Elixir target |
|--------|----------|---------------|
| `list.plus(x)` | List | `list ++ [x]` |
| `list.plusAll(l)` | List | `list ++ l` |
| `list.take(n)` | List | `Enum.take(list, n)` |
| `list.drop(n)` | List | `Enum.drop(list, n)` |
| `list.sum()` | List | `Enum.sum(list)` |
| `list.count()` | List | `Enum.count(list)` |
| `list.any { }` | List | `Enum.any?(list, fn)` |
| `list.all { }` | List | `Enum.all?(list, fn)` |
| `list.flatMap { }` | List | `Enum.flat_map(list, fn)` |
| `list.distinct()` | List | `Enum.uniq(list)` |
| `map.remove(k)` | Map | `Map.delete(map, k)` |
| `map.containsKey(k)` | Map | `Map.has_key?(map, k)` |
| `map.mapSize` | Map | `map_size(map)` |
| `str.endsWith(s)` | String | `String.ends_with?(str, s)` |
| `str.includes(s)` | String | `String.contains?(str, s)` |
| `str.replace(a, b)` | String | `String.replace(str, a, b)` |
| `str.toDouble()` | String | `String.to_float(str)` |

**How to test:**
```bash
mix run -e '
source = ~S"""
module Main {
    fun main() {
        val list = listOf(1, 2, 3, 4, 5)
        val extended = list.plus(6)
        val sum = extended.sum()
        println(sum.toString())

        val map = mapOf("a" to 1)
        val updated = map.put("b", 2)
        val removed = updated.remove("a")
        println(removed.containsKey("a").toString())

        val s = "hello world"
        println(s.includes("world").toString())
        println(s.endsWith("world").toString())
    }
}
"""
case Kore.compile(source, file: "test.kore") do
  {:ok, code} -> IO.puts(code)
  {:error, e} -> IO.puts(Kore.Errors.format_all(e))
end
'
```

**Expected:** Valid Elixir with `Enum.sum`, `Map.delete`, `Map.has_key?`, `String.contains?`, `String.ends_with?` calls.

---

#### 1.3 — Codegen for `:list_append` / `:list_concat`

**File changed:** `lib/kore/codegen/elixir.ex` (lines ~327-330)

**How to test:** Covered by `list.plus(x)` test above. Output should contain `list ++ [6]` not a function call.

---

#### 1.4 — Cleaned `@op_strings` in codegen

**File changed:** `lib/kore/codegen/elixir.ex` (line ~387)

**What changed:** Removed `plus_eq`, `minus_eq`, `elvis`, and `equal` from the BinOp string map (they have dedicated handlers or are now desugared).

**How to test:** The existing golden tests should still pass:
```bash
mix test test/golden_test.exs
```
If any golden tests output `+=` or `-=` in the Elixir code, something is wrong.

---

### Wave 1: Error Messages

#### 1.5 — Human-readable parser errors

**File changed:** `lib/kore/parser.ex`

**Changes:**
- `expect/2` now uses `token_display/1` (e.g., `Expected ')', got '{'` instead of `Expected rparen, got lbrace`)
- `parse_declaration` error names valid keywords
- `parse_prefix` error lists valid expression starters
- Dot-access error says "field or method name after '.'"
- Parser now returns `Kore.Errors` structs (not raw tuples)

**How to test:**
```bash
mix run -e '
source = "module Main { 123 }"
case Kore.compile(source, file: "bad.kore") do
  {:ok, _} -> IO.puts("unexpected success")
  {:error, [err | _]} ->
    IO.puts(Kore.Errors.format(err))
    # Should print human-readable message with quotes around tokens
end
'
```

**Expected:** Error message contains `Unexpected` and lists valid declarations.

```bash
mix test test/error_test.exs
```
Should pass (test was updated for new message format).

---

#### 1.6 — Improved scopes error

**File changed:** `lib/kore/semantics/scopes.ex`

**Change:** "early return not supported in v0.1" → "early return not supported; restructure using if/when expressions or move the return to the last position in the function body"

**How to test:**
```bash
mix run -e '
source = ~S"""
module Main {
    fun test(): Int {
        return 1
        val x = 2
        return x
    }
}
"""
case Kore.compile(source, file: "early_ret.kore") do
  {:ok, _} -> IO.puts("unexpected")
  {:error, errors} -> IO.puts(Kore.Errors.format_all(errors))
end
'
```

**Expected:** Error contains "early return not supported; restructure using if/when".

---

### Wave 1: Architecture

#### 1.7 — CLI split into sub-modules

**Files created:** `lib/kore/cli/scaffold.ex`, `lib/kore/cli/builder.ex`
**File modified:** `lib/kore/cli.ex`

**How to test:**
```bash
# Verify the escript still builds
mix escript.build

# Test scaffolding
./kore new /tmp/kore_test_project
ls /tmp/kore_test_project/  # should have kore.exs, lib/main.kore, .gitignore

# Test build (in a scaffolded project)
cd /tmp/kore_test_project && /path/to/kore build

# Test run
/path/to/kore run
# Expected: "Hello, KorE!"

# Cleanup
rm -rf /tmp/kore_test_project
```

---

#### 1.8 — Module documentation

**Files changed:** `lib/kore/parser.ex`, `lib/kore/lexer.ex`, `lib/kore/codegen/actor.ex`, `lib/kore/codegen/elixir.ex`, `lib/kore/codegen/specs.ex`

**How to test:** Just verify docs compile:
```bash
mix compile
```
Optional: `mix docs` if ex_doc is available — verify no warnings.

---

### Wave 2: Documentation

#### 2.1 — `docs/REFERENCE.md` (new, ~420 lines)

**Validates:** Complete grammar, type table, prelude signatures, name-mangling, error catalog, not-supported list.

**How to test:** Cross-reference key facts against the compiler:
- Keyword count: should list exactly 21 keywords (match `@keywords` in `lib/kore/lexer.ex`)
- Prelude entries: every method in `docs/REFERENCE.md` prelude table should have a matching clause in `lib/kore/prelude.ex`
- Error catalog: each error in the doc should be triggerable by feeding bad code to `Kore.compile/2`

---

#### 2.2 — `AGENTS.md` (new, repo root)

**Content:** Agent identity, workflow, project anatomy, quick syntax, 10 gotchas, not-supported, translation protocol, key references.

**How to test:** Verify links point to files that exist:
```bash
test -f docs/REFERENCE.md && echo "OK" || echo "MISSING: docs/REFERENCE.md"
test -f docs/ELIXIR_TO_KORE.md && echo "OK" || echo "MISSING: docs/ELIXIR_TO_KORE.md"
test -d examples/ && echo "OK" || echo "MISSING: examples/"
```

---

#### 2.3 — `docs/ELIXIR_TO_KORE.md` (new)

**Content:** Two-column Elixir→KorE translation table for modules, vars, data, patterns, control flow, collections, strings, null safety, Result, concurrency, interop, recursion patterns, and a worked GenServer example.

**How to test:** Take 3-4 "KorE" snippets from the translation table and compile them:
```bash
mix run -e '
source = ~S"""
module Main {
    fun main() {
        val list = listOf(1, 2, 3)
        val doubled = list.map { it * 2 }
        val sum = doubled.fold(0) { acc, x -> acc + x }
        println("Sum: ${sum}")
    }
}
"""
case Kore.compile(source, file: "test.kore") do
  {:ok, code} -> IO.puts("OK: compiles")
  {:error, e} -> IO.puts("FAIL:\n" <> Kore.Errors.format_all(e))
end
'
```

---

#### 2.4 — `docs/internals/IMPLEMENTATION.md` (moved)

**Was:** `docs/IMPLEMENTATION.md`
**Now:** `docs/internals/IMPLEMENTATION.md`

**How to test:** `test -f docs/internals/IMPLEMENTATION.md`

---

### Wave 2: Distribution

#### 2.5 — `install.sh`

**How to test:**
```bash
chmod +x install.sh
./install.sh
# Should: check for elixir/mix, run deps.get + compile + escript.build
# Output: "Success! KorE compiler built at: ..."
test -f ./kore && echo "escript exists" || echo "MISSING"
```

---

#### 2.6 — `.tool-versions`

**Content:** `erlang 26.2` + `elixir 1.16.0-otp-26`
**How to test:** If asdf is installed: `asdf install` should work.

---

#### 2.7 — `Dockerfile`

**How to test:**
```bash
docker build -t kore .
docker run --rm kore version
# Expected: "KorE 0.1.0"
```

---

#### 2.8 — `mix.exs` escript name

**Change:** Added `name: "kore"` to escript config.
**How to test:** After `mix escript.build`, the binary should be named `kore` (not `kore_cli` or similar).

---

#### 2.9 — `README.md` slimmed

**How to test:** Visual review — should be ~70-100 lines, contain quickstart, two install modes, CLI table, and doc links.

---

### Wave 3: Examples

#### 3.1 — `examples/` (10 projects)

Each must compile through the KorE pipeline without errors:

```bash
# Test all examples compile (no need to execute — just validate codegen)
for dir in examples/*/; do
  kore_file="$dir/lib/main.kore"
  if [ -f "$kore_file" ]; then
    result=$(mix run -e "
      source = File.read!(\"$kore_file\")
      case Kore.compile(source, file: \"$kore_file\") do
        {:ok, _} -> IO.puts(\"OK\")
        {:error, e} -> IO.puts(\"FAIL: \" <> Kore.Errors.format_all(e))
      end
    " 2>&1)
    echo "$dir: $result"
  fi
done
```

**Expected:** All 10 print "OK". If any fail, the example uses a construct not yet supported or has a syntax issue.

**Known potential issues to watch for:**
- `examples/05-recursion/` — self-recursive calls should "just work" but are untested in the golden suite
- `examples/06-actor-cache/` — uses `map.remove` and `map.mapSize` (new prelude entries)
- `examples/09-hex-deps/` — requires the Jason dep; test compilation only (codegen), not runtime
- `examples/10-todo-app/` — most complex; uses actors + `list.plus` + nested `if` inside lambda + compound `+=` in actor

---

### Wave 3: Skill

#### 3.2 — `.opencode/skills/kore/SKILL.md`

**How to test:** Verify file exists and is well-formed markdown:
```bash
test -f .opencode/skills/kore/SKILL.md && echo "OK"
head -5 .opencode/skills/kore/SKILL.md  # Should start with "# KorE Language Skill"
```

---

## Full Test Suite

After all fixes, the entire existing test suite must pass:

```bash
mix test
```

**If golden tests fail:** The parser/codegen changes may have altered output. Review the diffs:
```bash
KORE_UPDATE_GOLDEN=1 mix test test/golden_test.exs
git diff test/golden/cases/
```
If the changes are intentional (e.g., `&&` stayed as `&&`, removal of unreachable ops), regenerate and commit the golden files.

**If parser tests fail:** The `expect/2` messages changed format. Check `test/kore/parser_test.exs` for hardcoded error string assertions.

**If lexer tests fail:** The `@moduledoc` change shouldn't affect behavior, but verify.

---

## Validation Priority Order

1. `mix compile` — must succeed (prerequisite for everything)
2. `mix test` — existing tests must pass (may need golden regeneration)
3. `+=`/`-=` test (new feature)
4. New prelude methods test (new feature)
5. Error message format verification
6. CLI split functional test (`kore new` / `kore build` / `kore run`)
7. Examples compilation (all 10)
8. Doc cross-reference check (links, prelude table matches code)

---

## Files Changed (complete list)

### Modified (12):
- `lib/kore/parser.ex` — `+=`/`-=` support, error messages, moduledoc, `Kore.Errors` integration
- `lib/kore/prelude.ex` — 16 new method entries
- `lib/kore/codegen/elixir.ex` — list_append/concat handlers, cleaned @op_strings, moduledoc
- `lib/kore/codegen/actor.ex` — moduledoc
- `lib/kore/codegen/specs.ex` — moduledoc
- `lib/kore/lexer.ex` — moduledoc, @doc on tokenize
- `lib/kore/semantics/scopes.ex` — improved early-return error message
- `lib/kore/cli.ex` — slimmed to dispatcher, delegates to sub-modules
- `mix.exs` — escript name: "kore"
- `README.md` — rewritten (slim quickstart)
- `test/error_test.exs` — updated assertion for new error text
- `docs/IMPLEMENTATION.md` → moved to `docs/internals/IMPLEMENTATION.md`

### Created (48):
- `AGENTS.md`
- `docs/REFERENCE.md`
- `docs/ELIXIR_TO_KORE.md`
- `docs/internals/IMPLEMENTATION.md` (moved)
- `lib/kore/cli/scaffold.ex`
- `lib/kore/cli/builder.ex`
- `install.sh`
- `.tool-versions`
- `Dockerfile`
- `.opencode/skills/kore/SKILL.md`
- `.opencode/skills/kore/README.md`
- `examples/01-hello/` (3 files)
- `examples/02-data-modeling/` (3 files)
- `examples/03-collections/` (3 files)
- `examples/04-null-safety/` (3 files)
- `examples/05-recursion/` (3 files)
- `examples/06-actor-cache/` (3 files)
- `examples/07-spawn-receive/` (3 files)
- `examples/08-stdlib-interop/` (3 files)
- `examples/09-hex-deps/` (3 files)
- `examples/10-todo-app/` (3 files)
