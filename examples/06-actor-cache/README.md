# 06 - Actor Cache

Demonstrates KorE's actor model (backed by OTP GenServer):

- `actor` declaration with mutable state (`var`)
- `start()` to spawn the actor process
- Methods returning `Unit` become async casts (`put`, `remove`)
- Methods returning a value become sync calls (`get`, `size`)
- Nullable return type for missing keys
- Immutable map operations inside the actor

## Run

```sh
kore run
```

## Expected output

```
lang = KorE
size = 2
after remove, size = 1
```
