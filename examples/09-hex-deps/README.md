# 09 - Hex Dependencies

Demonstrates adding external Hex packages to a KorE project:

- `deps` field in `kore.exs` for Hex dependencies
- `import elixir.Jason` to use the Jason JSON library
- Encoding a KorE map to JSON
- Pattern matching on `Ok`/`Error` results from library calls

## Setup

Dependencies are fetched automatically on first `kore build`.

## Run

```sh
kore build && kore run
```

## Expected output

```
JSON: {"name":"KorE","version":"0.1.0"}
```
