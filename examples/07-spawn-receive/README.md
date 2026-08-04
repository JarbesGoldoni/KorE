# 07 - Spawn & Receive

Demonstrates low-level BEAM concurrency primitives:

- `spawn { ... }` to create a new process
- `send` to send a message to a PID
- `receive { ... }` to pattern-match on incoming messages
- `self()` to get the current process PID
- `Pair` as a simple message envelope

This is the raw process model. For stateful services, prefer `actor`.

## Run

```sh
kore run
```

## Expected output

```
Worker got: hello
Main got: echo: hello
```
