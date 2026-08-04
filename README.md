# KorE

**KorE** is a Kotlin-flavoured language that compiles to idiomatic Elixir and runs on the BEAM VM. Familiar Kotlin syntax — `fun`, `val`/`var`, `when`, data classes, sealed types, actors — with OTP superpowers underneath.

```kotlin
module Main {
    fun main() {
        val name = "world"
        println("Hello, $name!")
    }
}
```

## Getting Started

### Prerequisites

- Elixir >= 1.15, Erlang/OTP >= 25
- (Optional) [asdf](https://asdf-vm.com/) with `.tool-versions` included

### Install (global escript)

```bash
mix escript.install github JarbesGoldoni/KorE
```

### Install (vendored in your project)

```bash
git clone --depth 1 https://github.com/JarbesGoldoni/KorE.git .kore
.kore/install.sh
# Now use: .kore/kore build
```

### Docker

```bash
docker build -t kore .
docker run --rm -v "$PWD":/app kore build
```

## CLI Commands

| Command | Description |
|---------|-------------|
| `kore new <name>` | Scaffold a new KorE project |
| `kore build` | Compile `.kore` files to BEAM bytecode |
| `kore run [Module]` | Build and execute `Main.main()` (or given module) |
| `kore check` | Fast semantic validation without codegen |

## Documentation

- [Language Guide](docs/LANGUAGE_GUIDE.md) — syntax, types, actors, and examples
- [Reference](docs/REFERENCE.md) — type table, operators, and full grammar
- [Elixir to KorE](docs/ELIXIR_TO_KORE.md) — migration guide for Elixir developers
- [Implementation](docs/IMPLEMENTATION.md) — compiler architecture and passes

## For AI Agents

See [AGENTS.md](AGENTS.md) for context, conventions, and instructions when working on this codebase with AI coding agents.

## Development

```bash
mix deps.get
mix test                # full suite (unit, golden, runtime, diagnostics)
KORE_UPDATE_GOLDEN=1 mix test test/golden_test.exs  # regenerate golden files
```

## License

MIT — see [LICENSE](LICENSE).
