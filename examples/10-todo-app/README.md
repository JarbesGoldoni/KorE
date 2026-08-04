# 10 - Todo App

A complete mini-application combining multiple KorE features:

- `data` records with default values
- `sealed` command types (unused here but defined for extensibility)
- `actor` with mutable list state
- `var` fields and `+=` desugaring inside actors
- `copy` for toggling boolean fields
- Collection methods: `plus`, `map`, `isEmpty`, `forEach`
- Pattern matching with `if` expressions
- String interpolation in formatted output

## Run

```sh
kore run
```

## Expected output

```
=== All Todos ===
  [ ] 1. Learn KorE
  [ ] 2. Build something cool
  [ ] 3. Deploy to production

=== After completing #1 ===
  [x] 1. Learn KorE
  [ ] 2. Build something cool
  [ ] 3. Deploy to production
```
