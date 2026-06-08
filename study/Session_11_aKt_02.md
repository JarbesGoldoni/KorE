# 11.10 — The aKt Compiler Pipeline

## Overview

When you write a `.akt` file, the aKt compiler transforms it through five distinct phases before producing BEAM bytecode: parsing, type checking, static/dynamic analysis, code generation, and optimization. Each phase operates on a well-defined intermediate representation. This section walks through each phase in detail, using the `Counter.akt` component as a running example.

---

## The Parsing Phase

### Splitting the File

The compiler's first act is splitting the `.akt` file at the `---` separator. The algorithm scans for a line containing exactly `---` (three hyphens, nothing else, not even trailing whitespace) and splits on the first occurrence.

```
file content
───────────────────────────────
      │
      ▼
┌─── find first line == "---"
│
├── everything above → logic source text
└── everything below → template source text
```

If no `---` line is found, the compiler emits a hard error:

```
error[E0001]: .akt file missing `---` separator
 --> src/components/Counter.akt
  |
  | (entire file)
  |
  = hint: `.akt` files must have a logic section above `---` and a template section below
```

If the `---` line appears at the very beginning (empty logic section), this is permitted — the component has no logic, only a template. If it appears at the very end, the template section is empty, which is also a hard error since a component must render something.

The two resulting text spans are handed to separate parsers: the KorE parser for the logic section, and the aKt template parser for the template section. Both parsers share a single source file reference so that diagnostics report correct line numbers across the split.

---

### The Template AST

The template parser produces a tree of `TemplateNode` values. These are defined in the compiler's type system as a sealed hierarchy:

```kotlin
sealed class TemplateNode {

    /** A literal run of text with no embedded expressions. */
    data class TextNode(
        val content: String,
        val span: Span
    ) : TemplateNode()

    /** An HTML comment. Preserved in output for tooling; never sent over wire. */
    data class CommentNode(
        val content: String,
        val span: Span
    ) : TemplateNode()

    /**
     * A standard HTML element: <div>, <span>, <input />, etc.
     * Name is always lowercase.
     */
    data class ElementNode(
        val tag: String,
        val attributes: List<Attribute>,
        val children: List<TemplateNode>,
        val selfClosing: Boolean,
        val span: Span
    ) : TemplateNode()

    /**
     * A reference to another aKt component: <MyCounter />, <UserCard name={u.name} />.
     * Name begins with an uppercase letter.
     */
    data class ComponentNode(
        val name: String,                       // fully qualified after resolution
        val attributes: List<Attribute>,
        val slotChildren: Map<String, List<TemplateNode>>,  // named slots
        val defaultSlotChildren: List<TemplateNode>,        // default slot
        val span: Span
    ) : TemplateNode()

    /**
     * An embedded KorE expression: { someValue }, { user.name }, { if (x) "a" else "b" }.
     * The `expr` field is a full KorE ExpressionNode from the KorE expression AST.
     */
    data class ExpressionNode(
        val expr: kore.ast.ExpressionNode,
        val span: Span
    ) : TemplateNode()

    /**
     * A conditional block: @if / @else-if / @else.
     */
    data class ConditionalNode(
        val branches: List<CondBranch>,         // at least one; last may have null condition (else)
        val span: Span
    ) : TemplateNode() {
        data class CondBranch(
            val condition: kore.ast.ExpressionNode?,   // null = else branch
            val body: List<TemplateNode>
        )
    }

    /**
     * A loop: @for (item in collection).
     * `binding` is the loop variable name (a new identifier introduced into scope).
     * `indexBinding` is present for @for ((index, item) in collection).
     */
    data class LoopNode(
        val binding: String,
        val indexBinding: String?,
        val collection: kore.ast.ExpressionNode,
        val keyExpr: kore.ast.ExpressionNode?,  // from `key={expr}` attribute on loop children
        val body: List<TemplateNode>,
        val span: Span
    ) : TemplateNode()

    /**
     * A slot declaration inside a component definition: <slot /> or <slot name="actions" />.
     * Only valid inside a component definition template, not a usage site.
     */
    data class SlotNode(
        val name: String,           // "default" if no name attribute
        val fallback: List<TemplateNode>,
        val span: Span
    ) : TemplateNode()

    /**
     * A fragment: groups multiple nodes without a wrapping element.
     * Produced by <> ... </> syntax.
     */
    data class FragmentNode(
        val children: List<TemplateNode>,
        val span: Span
    ) : TemplateNode()
}
```

Attributes on elements and components are represented as:

```kotlin
sealed class Attribute {
    /** A literal string attribute: class="foo" */
    data class StaticAttribute(val name: String, val value: String, val span: Span) : Attribute()

    /** A dynamic attribute: class={expr} */
    data class DynamicAttribute(val name: String, val expr: kore.ast.ExpressionNode, val span: Span) : Attribute()

    /** A boolean attribute present with no value: disabled, checked */
    data class BooleanAttribute(val name: String, val span: Span) : Attribute()

    /** An event binding: onClick={handler} */
    data class EventAttribute(val eventName: String, val handler: kore.ast.ExpressionNode, val span: Span) : Attribute()

    /** A JS hook directive: use:Chart */
    data class HookAttribute(val hookName: String, val span: Span) : Attribute()

    /** The key attribute: key={expr} — must be a String expression */
    data class KeyAttribute(val expr: kore.ast.ExpressionNode, val span: Span) : Attribute()
}
```

---

### Recursive Expression Parsing

When the template parser encounters `{` inside an attribute value or text content, it hands control to the KorE expression parser. The boundary is defined by balanced `}` — the template parser does not attempt to parse the KorE expression itself, only to find where it ends by tracking brace depth.

```
template text: "Hello, { user.name }!"
                         ^^^^^^^^^^^
                         handed to KorE expression parser
                         returns ExpressionNode(MemberAccess(Identifier("user"), "name"))
                         template parser resumes after the closing }
```

This means any valid KorE expression is legal inside `{ }`, including function calls, `if`/`else` expressions, `when` expressions, `let` bindings, and lambdas. The KorE expression parser operates in "expression mode" (not statement mode), so declarations are not permitted inside `{ }`.

```kotlin
// Valid: KorE expression
{ if (count > 0) "items: $count" else "empty" }

// Valid: when expression
{ when (status) {
    Status.Active -> "active"
    Status.Pending -> "pending"
} }

// Valid: function call
{ formatDate(event.timestamp, "MM/dd/yyyy") }

// Invalid: declaration (parse error)
{ val x = 5 }  // error: declarations are not permitted in template expressions
```

---

### Disambiguating Components from Elements

The parser uses the case of the first character of the tag name to distinguish HTML elements from component references:

| Tag name | Example | Parsed as |
|---|---|---|
| Starts with lowercase | `<div>`, `<span>`, `<input />` | `ElementNode` |
| Starts with uppercase | `<Counter>`, `<UserCard />` | `ComponentNode` |

This is unambiguous because HTML element names are always lowercase (per spec), and KorE type names are always `PascalCase`. There is no overlap.

For namespaced components (`<Forms.TextInput />`), the parser recognizes any tag whose first segment is uppercase. The full dotted name is stored as a string in `ComponentNode.name` and resolved to a fully qualified module path during the resolution pass.

One edge case: SVG elements like `<foreignObject>` contain uppercase letters but do not start with uppercase. The parser uses only the first character as the discriminant, so `<foreignObject>` is correctly parsed as an `ElementNode`.

---

## The Type Checking Phase

### Template Scope

During type checking, the template section is given a scope derived from the logic section's declarations. The scope contains exactly:

- `props` — typed as the component's `props` record type (always present)
- `state` — typed as the component's state `data class` (only for `@LiveComponent`; referencing `state` in a `@Component` template is a type error)
- All top-level functions declared in the logic section
- All imported names visible in the logic section

No new identifiers can be declared in the template scope except for loop bindings introduced by `@for`. Every `{ expr }` node is type-checked against this scope extended with any active loop bindings.

### Prop Type Checking

When the type checker encounters a `ComponentNode`, it resolves the component name to its definition and retrieves the `props` record type. It then checks each attribute:

1. **Unknown attribute**: any attribute name not present in the `props` declaration is a compile error.
2. **Type mismatch**: the expression in `prop={expr}` must be assignable to the declared prop type.
3. **Missing required prop**: any prop without a default value that is not supplied at the usage site is a compile error.

```kotlin
// Declaration in UserCard.akt
props {
    val name: String
    val age: Int
    val avatar: String? = null   // optional, has default
}

// Usage
<UserCard name={user.name} age={user.age} />          // OK
<UserCard name={user.name} age={"forty"} />            // error: type mismatch, expected Int, got String
<UserCard name={user.name} />                          // error: required prop `age` not supplied
<UserCard name={user.name} age={40} title="Dr." />    // error: unknown prop `title`
```

The type checker resolves `ComponentNode.name` by searching the import graph. If the component cannot be resolved, it emits an unresolved reference error rather than a type error, since the prop types are unknown.

### Event Handler Type Checking

Every event attribute maps to an expected handler signature. The type checker verifies that the expression supplied as a handler value is a function reference (or lambda) whose type is assignable to the expected signature.

The full mapping of event name to expected signature:

| Attribute | Event type | Expected handler signature |
|---|---|---|
| `onClick` | `ClickEvent` | `(ClickEvent, State) -> State` or `(ClickEvent, State) -> Pair<State, List<Command>>` |
| `onInput` | `InputEvent` | `(InputEvent, State) -> State` or `(InputEvent, State) -> Pair<State, List<Command>>` |
| `onChange` | `ChangeEvent` | `(ChangeEvent, State) -> State` or `(ChangeEvent, State) -> Pair<State, List<Command>>` |
| `onSubmit` | `SubmitEvent` | `(SubmitEvent, State) -> State` or `(SubmitEvent, State) -> Pair<State, List<Command>>` |
| `onKeyDown` | `KeyEvent` | `(KeyEvent, State) -> State` or `(KeyEvent, State) -> Pair<State, List<Command>>` |
| `onKeyUp` | `KeyEvent` | `(KeyEvent, State) -> State` or `(KeyEvent, State) -> Pair<State, List<Command>>` |
| `onFocus` | `FocusEvent` | `(FocusEvent, State) -> State` or `(FocusEvent, State) -> Pair<State, List<Command>>` |
| `onBlur` | `FocusEvent` | `(FocusEvent, State) -> State` or `(FocusEvent, State) -> Pair<State, List<Command>>` |
| `onMouseEnter` | `MouseEvent` | `(MouseEvent, State) -> State` or `(MouseEvent, State) -> Pair<State, List<Command>>` |
| `onMouseLeave` | `MouseEvent` | `(MouseEvent, State) -> State` or `(MouseEvent, State) -> Pair<State, List<Command>>` |

For a `@Component` (stateless), event attributes are not permitted. The type checker emits an error if any event attribute is used on a stateless component's template, since there is no state to update.

A handler that is a partial application or lambda is also valid, as long as the resulting type matches:

```kotlin
// Direct function reference — valid
<button onClick={increment}>+</button>

// Lambda — valid
<button onClick={ event, state -> state.copy(count = state.count + 1) }>+</button>

// Wrong signature — compile error
<button onClick={handleClick}>+</button>
// error: `handleClick` has type (String) -> Unit but onClick requires (ClickEvent, State) -> State
```

### The `key` Attribute

The `key` attribute is special. Its value expression must have type `String`. If it has any other type, the compiler emits an error:

```
error[E0042]: `key` attribute must be a String expression
 --> Counter.akt:34
   |
34 |   <li key={item.id}> ... </li>
   |            ^^^^^^^
   = note: `item.id` has type `Int`; use `item.id.toString()` or a string interpolation
```

Additionally, if a `LoopNode` body contains `ElementNode` or `ComponentNode` children without a `key` attribute, the compiler emits a warning (not an error):

```
warning[W0010]: list children should have a `key` attribute for efficient diffing
 --> UserList.akt:12
   |
12 |   @for (user in state.users) {
13 |     <UserCard name={user.name} />
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   = hint: add `key={user.id.toString()}` to <UserCard>
```

### Renderable Type Checking

In `{ expr }` positions, the compiler checks that the expression type is one of the renderable types:

| Type | Rendering behavior |
|---|---|
| `String` | Rendered as escaped text content |
| `Int`, `Long`, `Float`, `Double` | Rendered via `.toString()` |
| `Boolean` | Rendered as `"true"` or `"false"` (rarely intended directly; compiler emits a hint to use conditional rendering instead) |
| `TemplateNode` (the virtual DOM type) | Rendered as a nested subtree |
| `List<TemplateNode>` | Each element rendered in order |
| `AsyncValue<T>` where `T` is renderable | Compiler expands to a pattern match; see §11.5 |
| `Unit` / `Nothing` / `null` | Not renderable; compile error |

Any other type in an `{ expr }` position is a compile error:

```
error[E0055]: type `User` is not renderable
 --> Profile.akt:8
  |
8 |   <p>{ user }</p>
  |        ^^^^
  = hint: access a field like `user.name`, or implement a `render()` extension
```

---

## Static/Dynamic Analysis

### The Classification Walk

After type checking succeeds, the compiler walks the template AST and classifies every node as either **static** or **dynamic**. A node is dynamic if:

- It is an `ExpressionNode` whose `expr` contains any reference to `props` or `state` (including transitively through function calls whose bodies reference `props` or `state`)
- It is an `ElementNode` or `ComponentNode` with at least one dynamic attribute or at least one dynamic child
- It is a `ConditionalNode` (always dynamic — the condition references `props` or `state` or the outcome would not be meaningful)
- It is a `LoopNode` (always dynamic — the collection references `props` or `state`)
- It is a `ComponentNode` with any dynamic prop values

A node is static if it contains no reference to `props` or `state` anywhere in its subtree. Static subtrees are extracted and compiled as binary string constants at the module level.

The analysis is a bottom-up pass: leaf nodes are classified first, then parents are classified based on their children. The classification is stored in the compiler's IR alongside each node.

### The `Rendered` Data Structure

The `Rendered` structure is an Erlang map that Phoenix LiveView's protocol uses for incremental DOM updates. The aKt compiler generates Erlang code that produces this map. Its structure is:

```erlang
%{
  :s => ["static0", "static1", "static2"],   %% static string parts in order
  0  => DynamicPart0,                         %% dynamic slot 0
  1  => DynamicPart1,                         %% dynamic slot 1
  ...
}
```

Where each dynamic part is either:
- A binary string (the rendered value of a dynamic expression)
- Another `Rendered` map (a nested component or conditional)
- A list of `Rendered` maps (a loop)

The static strings in `:s` are the literal HTML segments that surround and separate the dynamic slots. When the browser receives a `Rendered` map, it interleaves `:s[0]`, dynamic slot 0, `:s[1]`, dynamic slot 1, `:s[2]`, and so on to produce the full HTML string.

### Concrete Example

Take this template from `Counter.akt`:

```kotlin
<div class="counter">
  <h1>{ props.title }</h1>
  <p>Count: { state.count }</p>
  <button onClick={decrement}>-</button>
  <button onClick={increment}>+</button>
</div>
```

The static strings are everything except the two dynamic expression slots:

- static[0]: `<div class="counter"><h1>`
- static[1]: `</h1><p>Count: `
- static[2]: `</p><button phx-click="decrement">-</button><button phx-click="increment">+</button></div>`

The dynamic slots are:
- slot 0: `props.title`
- slot 1: `state.count`

The `Rendered` map produced at runtime looks like:

```erlang
%{
  :s => [
    "<div class=\"counter\"><h1>",
    "</h1><p>Count: ",
    "</p><button phx-click=\"decrement\">-</button>"
    "<button phx-click=\"increment\">+</button></div>"
  ],
  0 => <<"My Counter">>,    %% props.title
  1 => <<"42">>             %% state.count (integer rendered as string)
}
```

Note that the event handlers compile to `phx-click` data attributes (Phoenix LiveView's wire protocol attribute), not Erlang data in the `Rendered` map. Event bindings are static HTML attributes from the diff engine's perspective — they do not change unless the handler function itself changes, which cannot happen at runtime.

---

## Code Generation for Stateless Components

A `@Component` compiles to a single BEAM module with a single public function. There is no GenServer, no process, no state. The generated Erlang module looks like:

```erlang
-module('Elixir.MyApp.Components.Counter').
-export([render/1]).

%% Static string parts, hoisted as module attributes for zero-copy sharing
-define(S0, <<"<div class=\"counter\"><h1>">>).
-define(S1, <<"</h1><p>Count: ">>).
-define(S2, <<"</p></div>">>).

render(Props) ->
    Title = maps:get(title, Props),
    Count = maps:get(count, Props),
    #{
        s => [?S0, ?S1, ?S2],
        0 => to_binary(Title),
        1 => to_binary(Count)
    }.
```

`render/1` takes the props map and returns a `Rendered` map. It is called by whatever parent component includes this component in its template.

---

## Code Generation for Stateful Components

A `@LiveComponent` compiles to a GenServer module. The internal GenServer state holds the component's state, the current props, and the previous `Rendered` value for diffing.

### Generated Internal State

```erlang
-record(component_state, {
    state,           %% the KorE state data class (translated to an Erlang record)
    props,           %% current props map
    prev_rendered,   %% the Rendered map from the last render cycle (or nil)
    socket           %% the WebSocket/channel reference for sending diffs
}).
```

### Generated Callbacks

For `Counter.akt` with this logic section:

```kotlin
@LiveComponent
class Counter {

    props {
        val title: String
    }

    data class CounterState(val count: Int = 0)

    fun mount(props: CounterProps): CounterState = CounterState()

    fun increment(event: ClickEvent, state: CounterState): CounterState =
        state.copy(count = state.count + 1)

    fun decrement(event: ClickEvent, state: CounterState): CounterState =
        state.copy(count = state.count - 1)
}
```

The compiler generates:

```erlang
-module('Elixir.MyApp.Components.Counter').
-behaviour(gen_server).
-export([start_link/2, render/1, update/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% Static string parts
-define(S0, <<"<div class=\"counter\"><h1>">>).
-define(S1, <<"</h1><p>Count: ">>).
-define(S2, <<"</p><button phx-click=\"decrement\">-</button>"
              "<button phx-click=\"increment\">+</button></div>">>).

%% ──────────────────────────────────────────────────────────────
%%  Public API
%% ──────────────────────────────────────────────────────────────

start_link(Props, Socket) ->
    gen_server:start_link(?MODULE, {Props, Socket}, []).

%% Called by parent renderer; runs in the caller's process.
%% Returns a Rendered map.
render(Props) ->
    Title = maps:get(title, Props),
    Count = maps:get(count, Props, 0),
    #{s => [?S0, ?S1, ?S2], 0 => to_binary(Title), 1 => to_binary(Count)}.

%% Called when parent re-renders with new props.
update(Pid, NewProps) ->
    gen_server:cast(Pid, {update_props, NewProps}).

%% ──────────────────────────────────────────────────────────────
%%  GenServer callbacks
%% ──────────────────────────────────────────────────────────────

%% mount/1 maps to init/1.
%% Props come from the initial render context.
init({Props, Socket}) ->
    %% Call the KorE-generated mount function
    InitialState = mount(Props),
    ComponentState = #component_state{
        state = InitialState,
        props = Props,
        prev_rendered = nil,
        socket = Socket
    },
    %% Perform initial render and send to client
    {ok, do_render(ComponentState)}.

%% Event dispatch: onClick="increment" arrives as {event, "increment", EventPayload}
handle_call({event, <<"increment">>, RawPayload}, _From, CS) ->
    Event = decode_click_event(RawPayload),
    NewState = increment(Event, CS#component_state.state),
    NewCS = CS#component_state{state = NewState},
    FinalCS = do_render(NewCS),
    {reply, ok, FinalCS};

handle_call({event, <<"decrement">>, RawPayload}, _From, CS) ->
    Event = decode_click_event(RawPayload),
    NewState = decrement(Event, CS#component_state.state),
    NewCS = CS#component_state{state = NewState},
    FinalCS = do_render(NewCS),
    {reply, ok, FinalCS};

%% Prop update from parent re-render
handle_cast({update_props, NewProps}, CS) ->
    NewCS = CS#component_state{props = NewProps},
    FinalCS = do_render(NewCS),
    {noreply, FinalCS};

%% AsyncResult routing
handle_info({async_result, Name, Result}, CS) ->
    %% Dispatched to the correct handle_info clause by name
    dispatch_async_result(Name, Result, CS);

%% PubSub messages
handle_info({pubsub, Topic, Message}, CS) ->
    dispatch_pubsub(Topic, Message, CS);

handle_info(_Msg, CS) ->
    {noreply, CS}.

terminate(_Reason, _CS) ->
    ok.

%% ──────────────────────────────────────────────────────────────
%%  Internal render cycle
%% ──────────────────────────────────────────────────────────────

do_render(CS) ->
    NewRendered = render_template(CS#component_state.state, CS#component_state.props),
    Diff = compute_diff(CS#component_state.prev_rendered, NewRendered),
    case Diff of
        no_change ->
            CS;
        {changed, DiffMap} ->
            send_diff(CS#component_state.socket, DiffMap),
            CS#component_state{prev_rendered = NewRendered}
    end.

render_template(State, Props) ->
    Title = maps:get(title, Props),
    Count = State#counter_state.count,
    #{s => [?S0, ?S1, ?S2], 0 => to_binary(Title), 1 => to_binary(Count)}.
```

### How `Command` Values Are Processed

When an event handler returns `Pair<State, List<Command>>`, the compiler generates a command dispatch loop in the GenServer:

```erlang
process_commands([], CS) -> CS;
process_commands([Command | Rest], CS) ->
    NewCS = process_command(Command, CS),
    process_commands(Rest, NewCS).

process_command({async, Name, Fun}, CS) ->
    Self = self(),
    spawn(fun() ->
        Result = Fun(),
        Self ! {async_result, Name, {ok, Result}}
    end),
    CS;

process_command({subscribe, Topic}, CS) ->
    'Elixir.Phoenix.PubSub':subscribe('MyApp.PubSub', Topic),
    CS;

process_command({navigate, Path}, CS) ->
    send_navigate(CS#component_state.socket, Path),
    CS;

process_command({patch, Path}, CS) ->
    send_patch(CS#component_state.socket, Path),
    CS;

process_command({send_to_hook, HookName, EventName, Payload}, CS) ->
    send_hook_event(CS#component_state.socket, HookName, EventName, Payload),
    CS.
```

---

## The Diff Computation

The GenServer holds the previous `Rendered` map in `#component_state.prev_rendered`. After each render, it computes a diff:

```erlang
compute_diff(nil, New) ->
    {changed, New};   %% First render: send the full Rendered map

compute_diff(Prev, New) ->
    Diff = diff_maps(Prev, New),
    case maps:size(Diff) of
        0 -> no_change;
        _ -> {changed, Diff}
    end.

diff_maps(Prev, New) ->
    maps:fold(fun(Key, NewVal, Acc) ->
        PrevVal = maps:get(Key, Prev, undefined),
        case diff_value(PrevVal, NewVal) of
            same    -> Acc;
            {changed, V} -> maps:put(Key, V, Acc)
        end
    end, #{}, New).

diff_value(Same, Same) -> same;
diff_value(_Prev, New) when is_map(New) ->
    %% Nested Rendered map — recurse
    case diff_maps(_Prev, New) of
        Empty when map_size(Empty) =:= 0 -> same;
        PartialDiff -> {changed, PartialDiff}
    end;
diff_value(_Prev, New) ->
    {changed, New}.
```

The diff sent over the wire is a partial `Rendered` map containing only the keys whose values changed. The static `:s` key is never included in diffs after the initial render, since static strings cannot change.

**Example diff**: if only `state.count` changes from 42 to 43:

```erlang
%% Wire diff (only slot 1 changed)
%{1 => <<"43">>}
```

The browser runtime receives this, looks up slot 1 in its in-memory representation of the DOM, and updates only that text node. The rest of the DOM is untouched.

---

## Compile-Time Optimizations

### Static Part Hoisting

Static string segments are not generated inline in the `render_template` function. They are hoisted to module-level `-define` macros (which compile to binary constants in the BEAM module). This means the binary is allocated once when the module is loaded and shared across all render calls without copying.

### Dead Prop Detection

If a prop is declared in the `props` block but never referenced in either the logic section or the template, the compiler emits a warning:

```
warning[W0020]: prop `subtitle` is declared but never used
 --> Counter.akt:4
  |
4 |     val subtitle: String
  |         ^^^^^^^^
  = hint: remove it from the `props` block, or reference it in the template
```

### Unhandled `Command.async` Result

The compiler tracks every `Command.async("name")` call in event handlers and checks for a corresponding `handle_info(AsyncResult<"name", T>, state)` function. If none exists:

```
warning[W0030]: `Command.async("loadUser")` has no corresponding `handle_info` for its result
 --> UserProfile.akt:22
   |
22 |     Pair(state, listOf(Command.async("loadUser") { fetchUser(props.id) }))
   |                        ^^^^^^^^^^^^^^^^^^^^^^^^
   = hint: add `fun handle_info(msg: AsyncResult<"loadUser", User>, state: ProfileState): ProfileState`
   = note: the async task will run but its result will be silently discarded
```

This is a warning rather than an error because the async task may legitimately be fire-and-forget (triggering a side effect with no state update needed).

### Event Handler Signature Mismatch

This is a hard error, with a precise message identifying the mismatch:

```
error[E0060]: event handler `handleClick` has wrong signature for `onClick`
 --> Counter.akt:28
   |
28 |   <button onClick={handleClick}>Click me</button>
   |                    ^^^^^^^^^^^
   |
   = found:    (String) -> Unit
   = expected: (ClickEvent, CounterState) -> CounterState
              or (ClickEvent, CounterState) -> Pair<CounterState, List<Command>>
```

---

## Generated Modules for `pages/users/[id].akt`

For a page file at `pages/users/[id].akt`, the compiler generates the following BEAM modules:

| Module | Purpose |
|---|---|
| `MyApp.Pages.Users.Show` | The primary `@LiveComponent` GenServer for the page |
| `MyApp.Pages.Users.Show.Render` | Pure render functions, separated for testability |
| `MyApp.Pages.Users.Show.Router` | The Ping router binding that maps `/users/:id` to this page |
| `MyApp.Pages.Users.Show.DataLoader` | The `loadData/2` function, wrapped with error handling |

If a `_layout.akt` exists in `pages/users/`, it contributes:

| Module | Purpose |
|---|---|
| `MyApp.Pages.Users.Layout` | The layout component wrapping all pages in `pages/users/` |

---

## Complete Worked Example: Counter.akt

Given this `Counter.akt`:

```
@LiveComponent
class Counter {

    props {
        val title: String
    }

    data class CounterState(val count: Int = 0)

    fun mount(props: CounterProps): CounterState = CounterState()

    fun increment(event: ClickEvent, state: CounterState): CounterState =
        state.copy(count = state.count + 1)

    fun decrement(event: ClickEvent, state: CounterState): CounterState =
        state.copy(count = state.count - 1)
}

---

<div class="counter">
  <h1>{ props.title }</h1>
  <p>Count: { state.count }</p>
  <button onClick={decrement}>-</button>
  <button onClick={increment}>+</button>
</div>
```

**Phase 1 — Parse**:
- Logic section parsed by KorE parser → `ClassDeclaration(Counter, ...)`
- Template section parsed by template parser → `ElementNode(div, [StaticAttribute(class, "counter")], [...])`
- Expression nodes `{ props.title }` and `{ state.count }` parsed by KorE expression parser recursively

**Phase 2 — Type check**:
- Template scope: `{ props: CounterProps, state: CounterState, increment: ..., decrement: ... }`
- `props.title` → `String` → renderable ✓
- `state.count` → `Int` → renderable ✓
- `onClick={decrement}` → `(ClickEvent, CounterState) -> CounterState` → matches expected ✓
- `onClick={increment}` → `(ClickEvent, CounterState) -> CounterState` → matches expected ✓

**Phase 3 — Static/dynamic analysis**:
- `<div class="counter">` — static attribute, but has dynamic children → dynamic
- `<h1>{ props.title }</h1>` — contains reference to `props.title` → dynamic; h1 tags are static
- `<p>Count: { state.count }</p>` — contains reference to `state.count` → dynamic; "Count: " is static
- `<button onClick={decrement}>-</button>` — event handler compiles to static `phx-click` attribute → static leaf
- `<button onClick={increment}>+</button>` — same → static leaf
- Static strings extracted: `["<div class=\"counter\"><h1>", "</h1><p>Count: ", "</p><button ...>-</button><button ...>+</button></div>"]`
- Dynamic slots: 0 = `props.title`, 1 = `state.count`

**Phase 4 — Code generation**:
- `Elixir.MyApp.Components.Counter` GenServer module (shown above)
- `init/1` calls `mount/1`, stores `CounterState(count: 0)`
- `handle_call({event, "increment", _}, ...)` calls `increment/2`, updates state, re-renders
- `handle_call({event, "decrement", _}, ...)` calls `decrement/2`, updates state, re-renders
- `render_template/2` produces the `Rendered` map with static `:s` and dynamic slots 0 and 1

**Phase 5 — Optimization**:
- Static strings hoisted to `-define(S0, ...)`, `-define(S1, ...)`, `-define(S2, ...)`
- No dead props detected (`title` is used in template)
- No `Command.async` calls → no async result warnings
- Both event handlers verified ✓

**Initial `Rendered` sent to browser on first connect** (assuming `title = "My Counter"`, `count = 0`):

```erlang
#{
  s => [
    <<"<div class=\"counter\"><h1>">>,
    <<"</h1><p>Count: ">>,
    <<"</p><button phx-click=\"decrement\">-</button>"
      "<button phx-click=\"increment\">+</button></div>">>
  ],
  0 => <<"My Counter">>,
  1 => <<"0">>
}
```

**Diff sent after one increment** (count: 0 → 1):

```erlang
%{1 => <<"1">>}
```

Two bytes over the wire. The browser updates exactly one text node.

---

# 11.11 — JavaScript Interop

## The aKt JS Runtime

The browser-side aKt runtime (`akt-runtime`) is a small TypeScript library, distributed as an npm package, that manages everything between the browser and the BEAM server. It is not a Virtual DOM library and does not manage a component tree. Its responsibilities are:

**WebSocket management**: The runtime opens a single WebSocket connection to the server's channel endpoint on page load. It implements auto-reconnect with exponential backoff (base 500ms, max 30s, ±25% jitter), heartbeat pings every 30 seconds, and graceful reconnection that replays missed diffs by requesting a full render from the server.

**Diff application**: When a `Rendered` diff arrives over the WebSocket, the runtime looks up the component's current in-memory `Rendered` map, merges the diff into it, renders the full HTML string from the merged map by interleaving static and dynamic parts, and applies the resulting HTML to the DOM. The application step is a targeted `innerHTML` or `textContent` update on the smallest changed subtree, not a full page replacement.

**Event dispatch**: The runtime installs a single delegated event listener at `document.body` for each event type that aKt uses (`click`, `input`, `change`, `submit`, `keydown`, `keyup`, `focus`, `blur`). When an event fires, the runtime walks up the DOM tree from `event.target` to find the nearest `phx-click` (or equivalent) attribute, extracts the handler name and component ID, serializes the relevant event fields (target value, key name, mouse coordinates, etc.) to JSON, and sends the message over the WebSocket.

**Hook lifecycle management**: The runtime maintains a registry of hook instances keyed by DOM element. It calls `mounted()` when a hooked element is first added to the DOM, `beforeUpdate()` and `updated()` around each diff application that touches a hooked element, `beforeDestroy()` and `destroyed()` when a hooked element is removed, and `disconnected()`/`reconnected()` on WebSocket state changes.

**Client component hydration**: For `use client` islands, the runtime finds elements with `data-akt-island` attributes, deserializes their props from embedded JSON, imports the compiled JS bundle for the component, and calls the island's `hydrate(element, props)` function.

**Navigation**: `Command.navigate` and `Command.patch` arrive as server-push messages. `navigate` performs a full page transition using `window.history.pushState` followed by a re-mount of the new page's components. `patch` performs a URL update using `pushState` without a full remount, allowing partial page updates.

---

## JS Hooks — Full Reference

Hooks let you attach JavaScript objects to specific DOM elements. They are declared server-side with the `use:` directive and implemented client-side as plain JavaScript objects.

### Server-Side Declaration

```kotlin
// Attach a single hook
<canvas use:Chart data-config={Json.encode(chartConfig)} />

// Attach multiple hooks to one element
<div use:Draggable use:Resizable data-min-width="200" />

// Hooks can coexist with event handlers
<div use:InfiniteScroll onScroll={handleScroll} data-page={state.page.toString()} />
```

Each `use:HookName` compiles to a `phx-hook="HookName"` attribute on the element, plus a `data-akt-hook-id` attribute with a unique component-scoped identifier. Multiple hooks on one element compile to `phx-hook="Draggable Resizable"` (space-separated).

### Client-Side Hook Object

```javascript
const Chart = {
    // Called once when the element is first added to the live DOM.
    // Safe to initialize third-party libraries here.
    mounted() {
        const config = JSON.parse(this.el.dataset.config)
        this.chart = new ChartJS(this.el, config)

        // Subscribe to events pushed from the server to this hook
        this.handleEvent("highlight", ({ index }) => {
            this.chart.highlight(index)
        })
    },

    // Called immediately before the server applies a diff to this element.
    // Use to save state you want to restore after the update (scroll position, focus, etc.)
    beforeUpdate() {
        this.scrollY = this.el.scrollTop
    },

    // Called immediately after the server diff has been applied to this element.
    updated() {
        const config = JSON.parse(this.el.dataset.config)
        this.chart.update(config)
        this.el.scrollTop = this.scrollY
    },

    // Called before the element is removed from the DOM.
    // Use for cleanup that must happen before removal (e.g., stopping animations).
    beforeDestroy() {
        this.chart.stopAnimations()
    },

    // Called after the element has been removed from the DOM.
    // Use for final cleanup (removing event listeners, canceling timers).
    destroyed() {
        this.chart.destroy()
    },

    // Called when the WebSocket disconnects.
    // Use to show a stale-data indicator.
    disconnected() {
        this.el.classList.add("stale")
    },

    // Called when the WebSocket reconnects and state is re-synced.
    reconnected() {
        this.el.classList.remove("stale")
    },

    // Receives server-pushed events targeted at this hook by name.
    // (Alternative to registering with this.handleEvent in mounted.)
    handleEvent(name, payload) {
        if (name === "highlight") {
            this.chart.highlight(payload.index)
        }
    }
}
```

Hook objects are registered with the runtime before the WebSocket connection is opened:

```javascript
import { AktRuntime } from "akt-runtime"

const runtime = new AktRuntime({
    endpoint: "/akt/websocket",
    hooks: { Chart, Draggable, Resizable, InfiniteScroll }
})

runtime.connect()
```

### The `this` Context

Inside any hook lifecycle method, `this` provides:

```javascript
// The DOM element the hook is attached to
this.el  // → HTMLElement

// Send an event to the server component that owns this hook.
// The event arrives as handle_info(HookEvent<"name">, state) on the server.
// callback is called with the server's reply (optional).
this.pushEvent("chart_clicked", { index: 3 }, (reply) => {
    console.log("server acknowledged:", reply)
})

// Subscribe to a named event pushed from the server to this specific hook.
// Returns an unsubscribe function.
const unsub = this.handleEvent("highlight", (payload) => {
    this.chart.highlight(payload.index)
})

// Send an event to a specific component by CSS selector.
// Useful when a hook needs to communicate with a different component than its owner.
this.pushEventTo("#user-panel", "row_selected", { id: 42 })

// Initiate a file upload.
// `name` matches the upload declared with Command.allow_upload on the server.
this.upload("avatar", fileInputElement.files)

// Access the LiveSocket instance for advanced use cases.
this.liveSocket  // → AktRuntime instance
```

---

## The `pushEvent` / `handleEvent` Full Cycle

### Server Sending an Event to a Client Hook

```kotlin
// In DashboardComponent.akt logic section

fun handleHighlight(index: Int, state: DashState): Pair<DashState, List<Command>> =
    Pair(
        state.copy(highlightedIndex = index),
        listOf(Command.sendToHook("Chart", "highlight", mapOf("index" to index)))
    )
```

`Command.sendToHook` compiles to a `send_hook_event` call in the GenServer, which sends a server-push message over the WebSocket channel to the browser. The message is addressed to all hook instances named `"Chart"` within the component's scope.

### Client Receiving the Event

```javascript
const Chart = {
    mounted() {
        // Register a handler for the "highlight" event from the server
        this.handleEvent("highlight", ({ index }) => {
            this.chart.setHighlight(index)
        })
    }
}
```

The aKt runtime receives the server-push message, looks up all hook instances for the component, filters to those named `Chart`, and calls `handleEvent("highlight", payload)` on each.

### Client Sending an Event to the Server

```javascript
const Chart = {
    mounted() {
        this.el.addEventListener("click", (e) => {
            const index = getIndexFromPoint(e.offsetX, e.offsetY, this.chart)
            // Push an event to the server component that owns this hook
            this.pushEvent("chart_clicked", { index })
        })
    }
}
```

### Server Receiving the Event

```kotlin
// handle_info receives HookEvent messages
fun handle_info(msg: HookEvent<"chart_clicked">, state: DashState): DashState =
    state.copy(selectedIndex = msg.payload["index"] as Int)
```

`HookEvent<"chart_clicked">` is a KorE type that the compiler recognizes and routes to this `handle_info` function when the BEAM process receives a `{hook_event, "chart_clicked", Payload}` message. The `msg.payload` field is a `Map<String, Any>` deserialized from the JSON payload.

### The Wire Format

```
Client → Server:
{"type":"hook_event","hook":"Chart","name":"chart_clicked","payload":{"index":3}}

Server → Client:
{"type":"hook_event","hook":"Chart","name":"highlight","payload":{"index":3}}
```

---

## `use client` Components — Full Reference

### What `use client` Means

When the compiler sees `use client` as the first line of a `.akt` file, it routes the entire file to the TypeScript/JavaScript backend instead of the Erlang backend. The component is compiled to a JS bundle rather than BEAM bytecode.

However, the server still participates in two ways:
1. The initial HTML is server-rendered by executing the component's `mount` state computation on the server and building the initial DOM string.
2. Callbacks (event handlers passed as props from a parent server component) are serialized as event bindings and dispatched back to the parent server component over WebSocket when invoked.

### What the aKt-to-TS Compiler Generates

For a `use client` component, the compiler emits a TypeScript class:

```typescript
// Generated TypeScript for a use client SortableList component
export class SortableList {
    private state: SortableListState
    private props: SortableListProps
    private el: HTMLElement

    constructor(el: HTMLElement, props: SortableListProps) {
        this.el = el
        this.props = props
        this.state = this.mount(props)
        this.render()
    }

    private mount(props: SortableListProps): SortableListState {
        return { items: props.items, dragging: null }
    }

    private setState(newState: SortableListState) {
        this.state = newState
        this.render()
    }

    // Generated from KorE template
    private render() {
        this.el.innerHTML = this.renderTemplate(this.state, this.props)
        this.attachEvents()
    }

    private renderTemplate(state: SortableListState, props: SortableListProps): string {
        // ... generated from template AST
    }

    private attachEvents() {
        // ... generated event bindings
    }

    // Public: called by runtime when props change from server
    update(newProps: Partial<SortableListProps>) {
        this.props = { ...this.props, ...newProps }
        this.render()
    }
}
```

The compiled JS bundle is hashed and placed in the `priv/static/akt/` directory. The server knows the bundle path and emits it in the island mount metadata.

### Props Serialization

When a parent server component renders a `use client` island, it embeds the props as JSON in a `data-akt-props` attribute and the component name in a `data-akt-island` attribute:

```html
<div
  data-akt-island="SortableList"
  data-akt-bundle="/akt/sortable_list-a3f9e2.js"
  data-akt-props='{"items":["Alice","Bob","Charlie"],"onReorder":"__cb:reorder_users"}'
>
  <!-- Initial server-rendered HTML -->
  <ul>
    <li data-id="alice">Alice</li>
    <li data-id="bob">Bob</li>
    <li data-id="charlie">Charlie</li>
  </ul>
</div>
```

The client runtime finds all `[data-akt-island]` elements on page load, imports the bundle at `data-akt-bundle`, deserializes `data-akt-props`, and calls `hydrate(element, props)`. Hydration reuses the server-rendered HTML rather than replacing it (progressive hydration), attaching event listeners and initializing state without touching the DOM.

### Callback Serialization

When a parent server component passes a callback prop to a `use client` component:

```kotlin
// In parent server component template
<SortableList
    items={state.users.map { it.name }}
    onReorder={ ids -> handleReorder(ids, state) }
/>
```

The compiler detects that `onReorder` is a function prop passed to a `use client` component. It cannot serialize the lambda as a function. Instead, it:

1. Generates a unique callback binding name: `"__cb:reorder_users"` (derived from the prop name and component context)
2. Serializes the prop as the string `"__cb:reorder_users"` in the JSON props
3. Registers a `handle_info` handler in the parent GenServer for the `callback_invoked` message with this binding name

On the client side, the runtime deserializes props and recognizes `"__cb:reorder_users"` as a callback binding (the `__cb:` prefix is the discriminant). It replaces the string with a function that calls `this.pushEventTo(parentSelector, "callback_invoked", { name: "reorder_users", args: [...] })`.

When invoked in the client component:

```typescript
// Inside SortableList
this.props.onReorder(newOrderIds)
// → calls: pushEventTo("#parent-123", "callback_invoked", { name: "reorder_users", args: [newOrderIds] })
```

The server parent receives:

```kotlin
fun handle_info(msg: CallbackInvoked<"reorder_users">, state: ParentState): ParentState =
    handleReorder(msg.args[0] as List<String>, state)
```

### Complete `use client` Example

```kotlin
// components/SortableList.akt
use client

@Component
class SortableList {

    props {
        val items: List<String>
        val onReorder: (List<String>) -> Unit
    }

    data class SortableState(
        val items: List<String>,
        val draggingIndex: Int? = null
    )

    fun mount(props: SortableListProps): SortableState =
        SortableState(items = props.items)

    fun dragStart(event: DragEvent, state: SortableState): SortableState =
        state.copy(draggingIndex = event.target.dataset["index"]?.toInt())

    fun dragEnd(event: DragEvent, state: SortableState): SortableState {
        val newOrder = reorder(state.items, state.draggingIndex ?: return state, event.dropIndex)
        props.onReorder(newOrder)
        return state.copy(items = newOrder, draggingIndex = null)
    }
}

---

<ul class="sortable-list">
  @for ((index, item) in state.items) {
    <li
      key={index.toString()}
      class={ if (state.draggingIndex == index) "dragging" else "" }
      data-index={index.toString()}
      onDragStart={dragStart}
      onDragEnd={dragEnd}
      draggable
    >
      { item }
    </li>
  }
</ul>
```

---

## File Uploads

### Declaring an Upload

File uploads are declared in an event handler using `Command.allow_upload`. The declaration specifies the input name, accepted MIME types, maximum file size, and maximum number of files.

```kotlin
// In PageComponent.akt logic section

data class UploadState(
    val uploads: AsyncValue<List<String>> = AsyncValue.Loading,
    val uploadProgress: Map<String, Int> = emptyMap()
)

fun handleAllowUpload(event: ClickEvent, state: UploadState): Pair<UploadState, List<Command>> =
    Pair(state, listOf(
        Command.allow_upload("avatar",
            accept = listOf("image/png", "image/jpeg"),
            maxSize = 5 * 1024 * 1024,   // 5 MB
            maxFiles = 1
        )
    ))

fun handle_info(msg: UploadProgress<"avatar">, state: UploadState): UploadState =
    state.copy(uploadProgress = state.uploadProgress + (msg.ref to msg.percent))

fun handle_info(msg: UploadComplete<"avatar">, state: UploadState): Pair<UploadState, List<Command>> =
    Pair(
        state.copy(uploads = AsyncValue.Loading),
        listOf(Command.consume_uploaded("avatar") { entries ->
            entries.map { entry ->
                val dest = "/uploads/${entry.filename}"
                entry.copyTo(dest)
                dest
            }
        })
    )

fun handle_info(msg: AsyncResult<"consume_avatar", List<String>>, state: UploadState): UploadState =
    state.copy(uploads = AsyncValue.Ready(msg.value))
```

### The Template

```kotlin
<div class="upload-area">
  <input
    type="file"
    phx-upload="avatar"
    accept="image/png, image/jpeg"
  />

  @if (state.uploadProgress.isNotEmpty()) {
    @for ((ref, percent) in state.uploadProgress) {
      <div class="progress-bar">
        <div class="progress-fill" style="width: {percent}%"></div>
      </div>
    }
  }

  @when (state.uploads) {
    is AsyncValue.Ready -> {
      <p>Uploaded: { state.uploads.value.joinToString(", ") }</p>
    }
    is AsyncValue.Error -> {
      <p class="error">Upload failed: { state.uploads.message }</p>
    }
    else -> {}
  }
</div>
```

### How It Works

`Command.allow_upload` registers an upload slot in the component's GenServer. The aKt runtime on the client detects the `phx-upload` attribute, and when the user selects files, begins a chunked upload over the WebSocket (not a separate HTTP request). Progress messages arrive as `UploadProgress<"avatar">` `handle_info` calls. When all chunks are received, `UploadComplete<"avatar">` fires. `Command.consume_uploaded` runs the provided lambda in an async task that receives the completed upload entries — temporary file handles — and can move them to permanent storage.

---

## Script Tags and Global JS

### `<script>` in `.akt` Files

`<script>` tags are permitted only in layout files (`_layout.akt`) and page files (files in `pages/`). They are not permitted inside component files (files in `components/`). The tag must appear as a direct child of the template root, not nested inside elements.

```kotlin
// pages/_layout.akt — allowed
---
<html>
  <head>
    <script src="/akt/runtime.js" defer></script>
    <script>
      window.analyticsId = "UA-XXXXX"
    </script>
  </head>
  <body>
    <slot />
  </body>
</html>
```

Inline `<script>` tags in pages run once when the page is first loaded. They do not re-run on LiveView patches. If you need to run JS on each patch, use a hook.

### Global JS Includes

Global scripts and stylesheets belong in `pages/_layout.akt`'s `<head>` section. The `akt-runtime` bundle must be included here:

```kotlin
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <link rel="stylesheet" href="/assets/app.css" />
  <script src="/assets/akt-runtime.js" defer></script>
  <script src="/assets/app.js" defer></script>
</head>
```

### Page-Specific Head Elements

To inject page-specific `<title>`, `<meta>`, or `<link>` tags from a page component, use the `<head>` slot that the root layout exposes:

```kotlin
// pages/_layout.akt template section
<html>
  <head>
    <slot name="head" />           ← layout declares the head slot
    <link rel="stylesheet" href="/assets/app.css" />
    <script src="/assets/akt-runtime.js" defer></script>
  </head>
  <body><slot /></body>
</html>
```

```kotlin
// pages/users/[id].akt template section
<_layout>
  <template slot="head">          ← page fills the head slot
    <title>{ state.user.name } — MyApp</title>
    <meta name="description" content={state.user.bio} />
  </template>

  <div class="profile">
    ...
  </div>
</_layout>
```

The compiler verifies at compile time that the slot names match between the layout's `<slot name="...">` declarations and the page's `<template slot="...">` usages.

---

# 11.12 — Language Feature Requirements Inventory

This section is a precise, exhaustive list of everything aKt demands from the KorE compiler. Each entry specifies what is required, what the compiler must produce, which compiler phase handles it, and any open design questions.

---

## 1. `.akt` File Format Recognition

**What it is**: The KorE compiler must distinguish `.akt` files from `.kore` files and route them through the aKt compiler pipeline.

**What it must do**: The compiler's file loader checks the file extension. `.kore` files go through the standard KorE pipeline. `.akt` files are handed to the aKt pre-processor, which performs the `---` split before any further parsing. If a `.akt` file contains no `---` line, the compiler emits `E0001` and halts processing of that file. The split is on the first occurrence of a line equal to `"---"` after trimming trailing `\r` (for Windows line endings). Everything strictly above that line is the logic text; everything strictly below is the template text.

**Compiler phase**: File loading / pre-processing, before the parse phase.

**Open questions**: Should `.akt` files be permitted to import from `.kore` files and vice versa? Currently yes — the module system is shared. Should a `.akt` file be permitted to have no logic section (empty above `---`)? Currently yes, it produces a component with no declared handlers. Should the template section be permitted to be empty? Currently no — a component must render something.

---

## 2. Template AST Definition

**What it is**: The complete set of node types that the template parser produces. These are distinct from the KorE expression AST, though `ExpressionNode` embeds KorE expression nodes within it.

**What it must do**: The compiler defines the `TemplateNode` sealed class hierarchy (as shown in §11.10) in its internal type system. Template AST nodes carry `Span` references into the original `.akt` source file for diagnostics. The template AST is a separate type hierarchy from the KorE declaration/expression ASTs, but template `ExpressionNode` values contain `kore.ast.ExpressionNode` values as embedded fields.

**Compiler phase**: Defined in the compiler's IR module; populated by the template parser.

**Open questions**: Should `CommentNode` be preserved in the generated output or stripped? Current decision: stripped from the wire `Rendered` output but preserved in the AST for tooling (language server, syntax highlighting). Should there be a `RawHtmlNode` for `{@html expr}` style raw HTML injection? Currently not planned; a future security-sensitive addition.

---

## 3. Template Parser

**What it is**: A recursive descent parser for the template section of `.akt` files.

**What it must do**: The template parser implements the following grammar (informal notation):

```
template    ::= node*
node        ::= element | component | expression | conditional | loop | fragment | text | comment
element     ::= '<' LOWER_NAME attr* ('/' '>' | '>' node* '</' LOWER_NAME '>')
component   ::= '<' UPPER_NAME attr* ('/' '>' | '>' slot_content '</' UPPER_NAME '>')
expression  ::= '{' kore_expr '}'
conditional ::= '@if' '(' kore_expr ')' '{' node* '}' ('@else' 'if' '(' kore_expr ')' '{' node* '}')* ('@else' '{' node* '}')?
loop        ::= '@for' '(' binding 'in' kore_expr ')' '{' node* '}'
fragment    ::= '<>' node* '</>'
text        ::= [^<{@]+
comment     ::= '<!--' [^-->]* '-->'
attr        ::= LOWER_NAME '=' '"' text '"'         (static)
             |  LOWER_NAME '=' '{' kore_expr '}'    (dynamic)
             |  'on' UPPER_NAME '=' '{' kore_expr '}' (event)
             |  'use:' UPPER_NAME                   (hook)
             |  'key' '=' '{' kore_expr '}'         (key)
             |  LOWER_NAME                          (boolean)
```

The `kore_expr` production delegates to the KorE expression parser. The template parser passes the source position and remaining input to the KorE expression parser and receives back an `ExpressionNode` and the updated position. The two parsers share the source file reference.

**Compiler phase**: Parse phase, immediately after the `---` split.

**Open questions**: Should `@for` support destructuring bindings (`@for ((a, b) in pairs)`)? Currently yes, with `(a, b)` parsed as a destructure pattern. Should `@when` (exhaustive match, akin to Kotlin `when`) be a template directive? Currently planned as `@when (expr) { is Type -> { ... } }` but not yet specified in detail.

---

## 4. Template Scope Resolution

**What it is**: The mechanism by which identifiers in `{ expr }` template nodes are resolved to types and values.

**What it must do**: The compiler constructs a template scope record containing:
- `props`: bound to the component's props record type, always present
- `state`: bound to the component's state data class type, present only for `@LiveComponent`; a reference to `state` in a `@Component` template is a hard error
- All top-level function names declared in the logic section, with their function types
- All names imported into the logic section's module scope

This scope is passed to the KorE type checker when checking expressions inside `ExpressionNode` values. Loop bindings (`@for (item in list)`) extend this scope within their body.

Local variable declarations (`val x = ...`) are not permitted in the template. If the KorE expression parser encounters a `val` declaration inside `{ }`, the type checker emits an error. The rationale: template expressions are purely read-only projections of state and props. Logic that requires local variables belongs in the logic section as a helper function.

**Compiler phase**: Type checking phase.

**Open questions**: Should computed properties (functions of zero arguments) declared in the logic section be accessible as `props.derivedValue` via a getter syntax, or only as function calls `derivedValue()`? Current position: only as function calls. Should the template scope support `this` as a reference to the component instance? No — there is no `this` in aKt templates.

---

## 5. Component Prop Type Checking

**What it is**: Verification that every `<MyComponent prop={expr}>` usage matches the component's declared `props` block.

**What it must do**: When the type checker encounters a `ComponentNode`, it:
1. Resolves `ComponentNode.name` through the import graph to find the target `.akt` file
2. Reads the target component's `props` block to build a `PropSchema`: a map of prop name → `(type, required, default)`
3. For each attribute on the `ComponentNode`:
   - If `DynamicAttribute`, type-checks the expression and verifies assignability to the declared prop type
   - If `StaticAttribute` (a literal string), verifies the declared prop type is `String` or a type with a `String` constructor
   - Reports unknown attributes (attributes not in `PropSchema`) as errors
4. Verifies all required props (no default value, not nullable) are present; reports missing required props as errors
5. Verifies no required prop is listed twice; reports duplicate attributes as errors

Component resolution follows the module import rules. If the component is not importable (file not found, circular import, etc.), a resolution error is emitted rather than a prop error.

**Compiler phase**: Type checking phase, after import resolution.

**Open questions**: Should `data-*` attributes on component nodes be permitted (passed through to the root element)? Currently not permitted — `data-*` attributes belong on `ElementNode` values, and components control their own root element. Should `class` and `style` be mergeable across the usage site and the component's own template? Not yet designed.

---

## 6. Event Handler Type Verification

**What it is**: Verification that `onClick={handler}` and similar event bindings supply a function of the correct type.

**What it must do**: The compiler maintains the event-name-to-signature table shown in §11.10. For each `EventAttribute`, it:
1. Resolves the handler expression's type via the template scope
2. Looks up the expected signature for the event name
3. Verifies the handler type is assignable to either the `State`-returning or `Pair<State, List<Command>>`-returning variant
4. Emits `E0060` with found/expected types on mismatch

For `@Component` (stateless), any event attribute is immediately an error — there is no `State` type to supply.

Handler expressions may be:
- A bare function reference: `onClick={increment}` — type is looked up in scope
- A lambda: `onClick={ e, s -> s.copy(count = s.count + 1) }` — type is inferred
- A partial application: `onClick={ handleClick(context, _, _) }` — type is checked after partial application

**Compiler phase**: Type checking phase.

**Open questions**: Should custom event names (beyond the standard DOM events) be permitted? Yes — `onCustomEvent={handler}` should be supported for component-internal events, but the type checking rules for custom events are not yet designed. Should the handler be permitted to be a `val` of function type declared in the logic section, rather than a `fun`? Yes — any expression of the correct function type is permitted.

---

## 7. Static/Dynamic Split Implementation

**What it is**: The algorithm that classifies every template node as static (no runtime data dependency) or dynamic (depends on `props` or `state`).

**What it must do**: The compiler performs a bottom-up walk of the template AST. For each node, it computes a `Dependency` value:

```kotlin
enum class Dependency { Static, Props, State, Both }
```

The rules:
- `TextNode`: always `Static`
- `CommentNode`: always `Static`
- `ExpressionNode`: `Static` if the embedded KorE expression contains no references to `props` or `state`; `Props` if it references only `props.*`; `State` if it references only `state.*`; `Both` if it references both. The reference check is a free-variable analysis on the KorE expression AST.
- `ElementNode`: the maximum dependency of its attributes and children
- `ComponentNode`: the maximum dependency of its prop attributes
- `ConditionalNode`: always at least `Props` or `State` (since conditions reference runtime data); `Static` `ConditionalNode` values are a compile-time hint that the condition should be moved to the logic section, but not an error
- `LoopNode`: always at least the dependency of the collection expression
- `SlotNode`: `Static` if fallback contains no dynamic nodes, otherwise the dependency of its fallback
- `FragmentNode`: the maximum dependency of its children

A "static subtree" is any node with `Dependency.Static`. Static subtrees are serialized to HTML strings at compile time and stored as binary constants.

The split result is represented in the compiler IR as a `ClassifiedNode`, which wraps a `TemplateNode` with its `Dependency` and a slot index if dynamic.

**Compiler phase**: Static analysis phase, after type checking.

**Open questions**: Should function calls in template expressions be analyzed for `props`/`state` transitive dependencies (i.e., if `formatName(props.name)` calls a function, is the call classified as dynamic)? Current decision: any expression containing `props.*` or `state.*` as subexpressions is dynamic, regardless of whether it is wrapped in a function call. Tracking transitive purity through function bodies is possible but deferred.

---

## 8. `Rendered` Data Structure Generation

**What it is**: The exact Erlang term produced by the component's `render_template` function, and the code generation algorithm that produces it.

**What it must do**: The compiler, after the static/dynamic split, numbers each dynamic slot in template order (depth-first, left-to-right). It then generates:

1. A list of static string segments: the HTML surrounding and between dynamic slots, stored as module-level `-define` macros
2. A `render_template(State, Props)` function body that:
   - Builds the static `:s` list from the module-level constants
   - Evaluates each dynamic slot expression and inserts it at the corresponding integer key
   - For nested `ComponentNode` values, calls the sub-component's `render/1` function and nests the result as a nested `Rendered` map at the slot key

The static strings are computed at compile time by serializing static subtrees to HTML. Events compile to `phx-click="handler_name"` (or the equivalent for other event types). The `phx-*` attribute format is the Phoenix LiveView wire protocol, which the aKt JS runtime understands.

Nested component renders are represented as nested `Rendered` maps:

```erlang
%{
  s => ["<div>", "</div>"],
  0 => #{                    %% nested component's Rendered
    s => ["<span>", "</span>"],
    0 => <<"Alice">>
  }
}
```

**Compiler phase**: Code generation phase.

**Open questions**: For `ConditionalNode` and `LoopNode`, the number of dynamic slots varies at runtime. How is this represented in the `Rendered` structure? Answer: conditional branches are represented as nested `Rendered` maps at a single slot, with a special `:d` key indicating the branch index, allowing the diff algorithm to detect branch changes and send a full subtree replacement rather than a partial diff. Loops are represented as a list of `Rendered` maps. This is the same approach Phoenix LiveView uses. The full diff semantics for conditionals and loops are deferred to a later specification.

---

## 9. GenServer Generation for `@LiveComponent`

**What it is**: The full Erlang GenServer module the compiler emits for every `@LiveComponent`.

**What it must do**: The compiler generates a module that:

1. Defines a `-record(component_state, {state, props, prev_rendered, socket})` for the GenServer's internal state
2. Implements `init({Props, Socket})` by calling the KorE `mount/1` function, constructing the initial `component_state`, and performing an initial render
3. Generates one `handle_call({event, Name, Payload}, ...)` clause per event handler declared in the logic section, each calling `process_commands/2` after calling the handler function
4. Generates `handle_cast({update_props, NewProps}, CS)` for prop updates
5. Generates `handle_info({async_result, Name, Result}, CS)` dispatch by pattern matching on `Name` and routing to the correct KorE `handle_info` function
6. Generates `handle_info({pubsub, Topic, Msg}, CS)` dispatch similarly
7. Generates `handle_info({hook_event, Name, Payload}, CS)` for hook events
8. Generates `terminate/2` that calls any KorE `onDestroy` function if declared
9. Generates `do_render/1` as the internal render + diff + send cycle
10. Processes `Command` values via the `process_command/2` dispatch function

**Compiler phase**: Code generation phase.

**Open questions**: Should the GenServer be supervised? Yes — each `@LiveComponent` instance is started under a `DynamicSupervisor` managed by the aKt runtime. The supervisor is generated as part of the application's supervision tree by the router code generator. Should `@LiveComponent` support `code_change/3` for hot code upgrades? Deferred — the state data class would need a migration function.

---

## 10. Event Binding Compilation

**What it is**: How `onClick={handler}` in a template compiles to a wire-protocol attribute in the HTML output.

**What it must do**: Each event attribute compiles to a `phx-*` prefixed attribute on the HTML element. The handler function name is serialized as the attribute value. The mapping:

| aKt attribute | Compiled HTML attribute |
|---|---|
| `onClick={f}` | `phx-click="f"` |
| `onInput={f}` | `phx-change="f"` (mapped to change for input value tracking) |
| `onChange={f}` | `phx-change="f"` |
| `onSubmit={f}` | `phx-submit="f"` |
| `onKeyDown={f}` | `phx-keydown="f"` |
| `onKeyUp={f}` | `phx-keyup="f"` |
| `onFocus={f}` | `phx-focus="f"` |
| `onBlur={f}` | `phx-blur="f"` |

The event handler function name (as a string) is used as the attribute value. When the aKt JS runtime captures a `click` event on an element with `phx-click="increment"`, it sends `{type: "event", name: "increment", payload: {...}}` over the WebSocket. The GenServer's `handle_call` dispatch matches on `name` to invoke the correct handler.

Because event attributes compile to static HTML strings, they appear in the static segment of the `Rendered` structure and are never included in diffs. This means swapping event handlers at runtime by pointing `onClick` to a different function is not supported — the handler name is fixed at compile time. If conditional handler dispatch is needed, write a single handler that branches on state.

**Compiler phase**: Code generation phase (static string serialization).

**Open questions**: Should the payload include the full DOM event object, or only selected fields? Current answer: the aKt JS runtime serializes a typed subset based on the event type (e.g., `ClickEvent` gets `{x, y, button, altKey, ctrlKey, shiftKey, metaKey}`; `InputEvent` gets `{value}`). The full event object is never sent. Should debounce and throttle be declarable on event bindings? Yes — `onClick(debounce=300)={handler}` is planned but not yet specified.

---

## 11. `Command.async` Result Routing

**What it is**: The compile-time tracking and runtime routing of async task results to their `handle_info` handlers.

**What it must do**:

At compile time, the compiler collects all `Command.async("name")` calls in event handlers and all `handle_info(msg: AsyncResult<"name", T>)` function declarations. It builds two sets:
- `asyncNames`: the set of all async task names used in `Command.async`
- `handledNames`: the set of all async names with a corresponding `handle_info`

For each name in `asyncNames` not in `handledNames`, emit warning `W0030`.

At code generation time, the `handle_info` dispatch for `{async_result, Name, Result}` messages is a generated pattern match:

```erlang
handle_info({async_result, <<"loadUser">>, {ok, Result}}, CS) ->
    %% dispatch to KorE handle_info for AsyncResult<"loadUser", User>
    NewState = handle_info_load_user({async_result_ok, <<"loadUser">>, Result}, CS#component_state.state),
    NewCS = CS#component_state{state = NewState},
    {noreply, do_render(NewCS)};

handle_info({async_result, <<"loadUser">>, {error, Reason}}, CS) ->
    NewState = handle_info_load_user({async_result_err, <<"loadUser">>, Reason}, CS#component_state.state),
    NewCS = CS#component_state{state = NewState},
    {noreply, do_render(NewCS)};
```

The `AsyncResult<"name", T>` type in KorE is a compile-time marker that generates the correct pattern match arms. The `T` type parameter is used for type checking the handler signature but erased at the Erlang level — Erlang does not enforce the type of the `Result` field.

**Compiler phase**: Static analysis (warning detection), code generation (dispatch generation).

**Open questions**: Should unhandled async results cause the GenServer to log an error at runtime rather than silently discard? Current position: yes, a `Logger.warn` call is emitted in the catch-all `handle_info` clause for unrecognized async result names, as a defense in depth measure. Should `Command.async` support a timeout? Planned: `Command.async("name", timeout = 5000) { ... }` with automatic `{async_result, Name, {error, timeout}}` on expiry.

---

## 12. File-Based Routing Code Generation

**What it is**: The algorithm that scans the `pages/` directory and generates a Ping router module.

**What it must do**:

1. Recursively scan the `pages/` directory for `.akt` files
2. For each file, compute the URL path:
   - `pages/index.akt` → `/`
   - `pages/about.akt` → `/about`
   - `pages/users/index.akt` → `/users`
   - `pages/users/[id].akt` → `/users/:id`
   - `pages/users/[id]/posts/[postId].akt` → `/users/:id/posts/:postId`
   - `pages/[...all].akt` → `/*all` (catch-all)
3. Detect special files:
   - `_layout.akt` in any directory: the layout component wrapping all pages at that level and below
   - `_loading.akt`: the loading state component shown during `loadData` execution
   - `_error.akt`: the error boundary component shown when `loadData` throws or a page crashes
4. Verify all page-level `.akt` files are `@LiveComponent` (not `@Component`); emit an error otherwise
5. Generate a Ping router module:

```kotlin
// Generated: MyApp.Router (Ping DSL)
router {
    scope("/") {
        layout(MyApp.Pages.Layout)

        get("/", MyApp.Pages.Index, loading = MyApp.Pages.Loading)
        get("/about", MyApp.Pages.About)
        get("/users", MyApp.Pages.Users.Index)
        get("/users/:id", MyApp.Pages.Users.Show, loading = MyApp.Pages.Users.Loading)
        get("/users/:id/posts/:postId", MyApp.Pages.Users.Posts.Show)
    }
}
```

**Compiler phase**: A post-processing step that runs after all `.akt` files in `pages/` have been individually compiled, generating the router module as a final artifact.

**Open questions**: Should file-based routing support POST/PUT/DELETE routes for API endpoints? Current answer: no — aKt pages are GET-only LiveView routes. API routes are declared manually in the Ping router. Should parallel routes (Next.js-style) be supported? Not planned for initial release.

---

## 13. Client Component (`use client`) Bundling

**What it is**: The separate compilation path for `use client` `.akt` files, which targets TypeScript/JavaScript instead of Erlang.

**What it must do**:

1. Detect `use client` as the literal first line of the `.akt` file (before any comments, whitespace, or annotations)
2. Route the file to the TS/JS compiler backend instead of the Erlang backend
3. The TS/JS backend performs the same parse and type checking phases but generates TypeScript rather than Erlang
4. Emits:
   - A TypeScript class file in `priv/static/akt/src/`
   - A compiled and hashed JS bundle in `priv/static/akt/` after running the bundler (esbuild)
   - A server-side Erlang module containing `render_initial/1`, which performs the initial SSR by executing the component's `mount` function in Erlang (the `mount` function is compiled twice: once to TS for client execution, once to Erlang for SSR)
5. The prop serialization format: JSON, with function/callback props serialized as `"__cb:<binding_name>"` strings
6. The island mount metadata embedded in the HTML: `data-akt-island`, `data-akt-bundle`, `data-akt-props` attributes on the component's root element

The `mount` function is the only function compiled to both targets. All other logic (event handlers, helper functions) is compiled only to the TS target. This means `use client` components cannot use KorE standard library functions that have no TS equivalent — the compiler flags such usages at the TS code generation phase.

**Compiler phase**: Detected in pre-processing; handled by the TS/JS backend during parse, type check, and code generation phases.

**Open questions**: Should `use client` components support `Command`-style effects on the client? Currently not — client components manage their own state and communicate with the server only via prop callbacks and `pushEvent`. A `Command`-like system for client components is a potential future addition. Should the bundler be configurable (webpack, rollup) or fixed (esbuild)? Fixed at esbuild for the initial release; the bundler integration is an internal implementation detail.

---

## 14. The aKt Runtime JS Library

**What it is**: The browser-side `akt-runtime` npm package.

**Public APIs**:

```typescript
// Main entry point
new AktRuntime(config: AktConfig): AktRuntime

interface AktConfig {
    endpoint: string           // WebSocket endpoint path, e.g. "/akt/websocket"
    hooks?: Record<string, Hook>   // hook objects keyed by name
    params?: Record<string, string> // query params sent on connect (e.g. CSRF token)
    logger?: Logger
}

// AktRuntime instance methods
runtime.connect(): void
runtime.disconnect(): void
runtime.getSocket(): WebSocket
runtime.pushEvent(target: string | Element, name: string, payload: object): void
runtime.handleEvent(name: string, callback: (payload: object) => void): () => void

// Hook interface
interface Hook {
    mounted?(): void
    beforeUpdate?(): void
    updated?(): void
    beforeDestroy?(): void
    destroyed?(): void
    disconnected?(): void
    reconnected?(): void
    handleEvent?(name: string, payload: object): void
}
```

**What it does NOT provide (by design)**:
- No Virtual DOM. There is no diffing of a component tree on the client. All diffing happens on the server. The client only applies pre-computed diffs.
- No component tree. The client has no knowledge of component hierarchy. Components are server concepts.
- No React-style hooks (`useState`, `useEffect`, etc.). Client state lives either on the server (in `@LiveComponent`) or in `use client` island components. The runtime does not manage state.
- No routing logic beyond History API navigation commands received from the server.
- No templating engine. Templates are compiled server-side and sent as pre-rendered HTML.

**Size target**: The aKt runtime aims for a compressed size comparable to Alpine.js (approximately 15–20 kB gzipped). It is not comparable to React (45 kB+) or Vue (33 kB+) because it does not include a Virtual DOM or component model. The runtime's responsibilities are WebSocket management, diff application, event delegation, and hook lifecycle — all of which are implementable in a small footprint.

**Package distribution**: Published as `akt-runtime` on npm. Versioned alongside the aKt compiler — a compiler version pin in `build.gradle.kts` specifies which `akt-runtime` version is compatible. The runtime is included in the generated `priv/static/` directory by the aKt build plugin, so manual npm installation is not required for standard aKt projects; it is only needed for projects that customize their JS build pipeline.