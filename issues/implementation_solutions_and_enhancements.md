# KorE Web App Implementation Issues, Solutions & Language Recommendations

### Documented by: AI Pair Programmer (2026-08-04)
### Project context: Real-Time WhatsApp Web Chat App (`web_app`)

---

## 1. Summary of Issues Encountered & Resolution Strategies

### Issue 1: `Process.register` Crash on Server Restart
- **Problem**: Calling `Process.register(store, :chat_store)` threw an Elixir `ArgumentError` when restarting the server because `:chat_store` was already bound to an active process from a previous run.
- **Expected**: A safe registration mechanism or non-crashing process binding.
- **Solution**: Guarded the process registration using `Process.whereis`:
  ```kotlin
  if (Process.whereis(:chat_store) == null) {
      val store = ChatStore.Store.start()
      Process.register(store, :chat_store)
  }
  ```

### Issue 2: Modulo `%` and Integer Math (`rem`, `div`, `trunc`)
- **Problem**: The `%` character in Elixir is reserved for map/struct literals (`%{...}`). Writing `len % 8` or `len / 8` produced floats in BEAM (`len / 8 = 0.625`), causing argument errors when calling integer formatting functions. Calling `:erlang.trunc` generated `GenServer.call(:erlang, ...)` because KorE treated `:erlang` as an un-registered actor name.
- **Expected**: Native support for integer division (`div`), modulo (`rem`), and truncation (`trunc`).
- **Solution**: Updated the KorE compiler codebase (`lib/kore/codegen/elixir.ex` and `lib/kore/prelude.ex`):
  1. Added `"Kernel"`, `"Integer"`, `"DateTime"`, `"NaiveDateTime"`, and `"Application"` to the `is_external` module whitelist in `lib/kore/codegen/elixir.ex`.
  2. Added `"rem"`, `"div"`, and `"trunc"` to `lookup_function` in `lib/kore/prelude.ex`.
  3. Recompiled the KorE CLI escript via `mix escript.build`.
  4. Now `Kernel.rem(len, 8)` and `Kernel.div(secInDay, 3600)` compile cleanly to Elixir's `Kernel.rem` and `Kernel.div`.

### Issue 3: Missing Application Boot Supervisor (`Application.ensure_all_started`)
- **Problem**: Starting Cowboy with `Cowboy.http(...)` without ensuring the `:plug_cowboy` application was booted resulted in HTTP `500 Internal Server Error` on response calls because Plug adapter state processes were uninitialized.
- **Expected**: `Application.ensureAllStarted(:plug_cowboy)` to start the Erlang `:plug` and `:ranch` supervision tree.
- **Solution**: Whitelisted `Application` in KorE codegen and called `Application.ensureAllStarted(:plug_cowboy)` at the top of `main.kore`.

### Issue 4: Actor State Mutation Lost in Methods with Return Types
- **Problem**: An actor method declared with a return type (e.g. `fun addMessage(...): Message`) generated a `handle_call` wrapper in Elixir:
  ```elixir
  kore_ret = (fn -> 
    msg = Kore.ChatStore.Message.new(...)
    messages = messages ++ [msg]
    msg
  end).()
  {:reply, kore_ret, %{state | messages: messages, next_id: next_id}}
  ```
  Because Elixir variables defined inside an anonymous function `(fn -> ... end).()` do not mutate outer function scope, `messages` in `state` remained un-mutated.
- **Expected**: Actor methods that modify state variables (`var messages`, `var nextId`) to persist state updates regardless of return type.
- **Solution**: Modified `addMessage` in KorE to return `Unit` (no return type annotation). KorE compiler then emitted `handle_cast`, which directly mutates `messages` and `next_id` in GenServer state without an anonymous function wrapper:
  ```elixir
  def handle_cast({:add_message, username, text, color, timestamp}, state) do
    messages = state.messages ++ [msg]
    {:noreply, %{state | messages: messages}}
  end
  ```

### Issue 5: Double-Quote Escaping in String Literals (`\"`)
- **Problem**: Writing regex replace strings like `.replace(/\"/g, ...)` inside KorE string literals was parsed as ending the string literal early, corrupting generated JavaScript in HTML templates.
- **Expected**: Escaped quotes `\"` to be preserved inside KorE string literals.
- **Solution**: Avoided unescaped double quotes inside JS string functions by using `String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')`.

---

## 2. Recommendations for KorE Language Enhancements

To make building web applications and full-stack services easier and more intuitive in KorE:

1. **Native Integer Division & Modulo Operators**:
   - Transpile `a / b` (when `a` and `b` are `Int`) to `div(a, b)` in Elixir, and provide `%` transpiling to `rem(a, b)`.

2. **Actor Method State Mutation Support**:
   - Update `lib/kore/codegen/actor.ex` so that anonymous function wrappers `(fn -> ... end).()` inside `handle_call` re-assign mutated `var` fields to the outer scope before returning `{:reply, kore_ret, state}`.

3. **Multi-line Triple-Quoted Raw Strings (`"""..."""`)**:
   - Add support for raw multiline strings so complex HTML/CSS/JS templates can be embedded naturally without string concatenation `+` or escaping bugs.

4. **Automatic External Module Recognition**:
   - Automatically treat any capitalized module identifier `Module.func(...)` imported with `import elixir.Module` as an external Elixir module rather than prepending `Kore.` namespace.

5. **Built-in `kore test` File Matcher**:
   - Update `lib/kore/cli/builder.ex` so `kore test` copies both `test/**/*.kore` AND `test/**/*.exs` files into `_build/kore_gen/test/` to support standard Mix ExUnit test suites out of the box.

---

## 3. KorE Codebase Changes Made in this Task

- **`lib/kore/codegen/elixir.ex`**: Whitelisted `Kernel`, `Integer`, `DateTime`, `NaiveDateTime`, and `Application` in `is_external`.
- **`lib/kore/prelude.ex`**: Added `rem`, `div`, and `trunc` top-level function mappings.
- **`kore` (escript binary)**: Recompiled via `mix escript.build`.
