# 08 - Stdlib Interop

Demonstrates calling Elixir standard library modules from KorE:

- `import elixir.Module` to bring Elixir modules into scope
- Calling `System.systemTime()` for timestamps
- Using `Enum.shuffle` and `Enum.uniq` on KorE lists
- Seamless interop between KorE types and Elixir functions

## Run

```sh
kore run
```

## Expected output (non-deterministic)

```
System time: <nanosecond timestamp>
Shuffled: <random order of 3, 1, 4, 1, 5>
Unique: [3, 1, 4, 5]
```
