# Session 11: aKt — The BEAM-Native Component UI Framework

---

## 11.1 — Philosophy & Design Principles

aKt is a bet on a specific claim: the React component model is the right abstraction for building UI, but the browser is the wrong place to run it.

React's fundamental insight was that UI is a function of state — `UI = f(state)` — and that components composing into trees is the right structural unit. That insight is correct and worth preserving. What React got wrong, or rather what became a burden as applications scaled, is that this state lives in the browser. The consequences are well-known: hydration cost, bundle size, stale closure bugs, complex async coordination, network waterfalls for data fetching, and an entire ecosystem of libraries (React Query, Zustand, Redux, SWR, Jotai) that exist to manage the accidental complexity of client-side state.

Phoenix LiveView demonstrated that the browser can be a thin terminal. State lives on the server. The server computes diffs and sends minimal patches over a persistent WebSocket. The browser applies patches to the DOM. The result is rich interactivity with near-zero client JavaScript. But LiveView's developer experience is foreign to React developers: `.heex` templates, Elixir's functional syntax, Phoenix-specific patterns. The learning curve is the adoption barrier.

aKt's design mandate is to remove that barrier without surrendering the execution model. A React developer should open a `.akt` file and recognize it immediately. The mental model migration from hooks to server processes should be the largest conceptual shift required — not the syntax.

---

### The Five Core Principles

**Principle 1: One file, one component**

React/Next.js: A `.tsx` file defines a component. Logic and markup live in the same file. Props are typed interfaces. This is natural, and React developers have strong muscle memory for it.

LiveView: A LiveView module is an Elixir module with callbacks. Templates are typically in separate `.heex` files or in an embedded heredoc. The connection between the module and its markup is indirect.

aKt: A `.akt` file is a single-file component. KorE logic (props declaration, event handlers, lifecycle, state) and markup live in the same file, separated by a clear structural boundary. There is no separate template file. The file compiles to one or more BEAM modules. The component's identity is the file.

This is non-negotiable for developer experience. The cognitive overhead of navigating between a module file and a template file creates friction. Single-file components eliminate it.

**Principle 2: State lives on the server; the browser is a display terminal**

React/Next.js: Component state (`useState`, `useReducer`, `useContext`) lives in the browser's JavaScript heap. Changes to state trigger re-renders in the virtual DOM. The browser is doing real computational work. Server Components (React 19+) run on the server but cannot hold state — they are stateless render functions.

LiveView: The LiveView process IS the component. State is `socket.assigns`. When assigns change, `render/1` is called, a diff is computed against the previous render, and only the changed parts are sent over the WebSocket. The browser receives a patch and applies it. The browser runs no component logic.

aKt: Stateful `.akt` components compile to GenServer processes. `assign()` is how state changes. The render function is called on every state change. The browser receives diffs. There is no virtual DOM in the browser, no React reconciler, no hydration step. The browser's JavaScript is a thin diff-applicator. This is not a limitation — it is a feature. State is always consistent because there is only one copy of it, living in one process.

**Principle 3: Data fetching is a function call, not a network request**

React/Next.js: Components run in the browser. Fetching data means making HTTP requests (`fetch`, `axios`), managing loading and error states (`useEffect`, React Query, SWR, `use()`), handling race conditions, and keeping client state in sync with server state. React Server Components (Next.js App Router) partially solve this — they run on the server and can fetch data directly — but they cannot hold state, so dynamic components still require client-side data management.

LiveView: LiveView processes run on the BEAM. Database calls are local function calls. There is no network between the component and the database. `onMount` equivalent (`mount/3`) runs on the server and can call Ecto directly. There is no "loading" phase for synchronous data — the data is there before the first render.

aKt: This is the clearest win over React to communicate to developers. There is no `useEffect(() => fetch('/api/users'), [])` pattern. There is no API route to write for data that only the component needs. `onMount` runs on the BEAM and calls services directly. The component receives fully loaded data on first render. For slow operations (external API calls), `assignAsync` provides explicit loading states — but this is the exception, not the rule. The rule is: your data is a function call away.

**Principle 4: Real-time is the default, not a feature**

React/Next.js: Real-time requires explicit infrastructure: WebSocket clients, state management integration, reconnection logic, React state updates from socket events. Libraries like Socket.io, Pusher, or Ably exist to manage this. The component must be written with real-time in mind from the start — retrofitting it is painful.

LiveView: The WebSocket connection is always open. Subscribing to PubSub in `mount/3` and handling broadcasts in `handle_info/2` is idiomatic. Presence tracking is built in. The component is, architecturally, a process that can receive messages — real-time is not an add-on, it is the execution model.

aKt: A stateful component IS a process. Subscribing to PubSub in `onMount` and handling `handle_info` is first-class in aKt's component model. A notification component that updates in real-time across all browser tabs is not a special case — it is the same pattern as a component that updates when a button is clicked. This should be surfaced explicitly in aKt's design, not hidden.

**Principle 5: The compiler is the safety boundary**

React/Next.js: TypeScript provides compile-time prop checking. But the boundary between server and client code (in Next.js App Router) requires runtime checks, and the serialization of data across the server/client boundary is partially runtime behavior. Prop type mismatches are caught by TypeScript but not always at the call site in templates.

LiveView: Erlang/Elixir are dynamically typed. LiveView has no compile-time prop checking. Template errors surface at runtime.

aKt: KorE's gradual sound typing, applied to `.akt` files, means that prop types are checked at call sites in markup. If `<UserCard userId={user.id} />` appears in a template and `userId` expects an `Int` but `user.id` is a `String`, that is a compile error. Event handler references in markup are validated against the component's declared handlers. The compiler knows the full interface of every component and enforces it. This is the synthesis: React's TypeScript discipline applied to a LiveView execution model.

---

## 11.2 — The `.akt` File Format

The file format is the most consequential design decision in aKt. It determines:

- How natural the file feels to a React developer
- What the parser must handle
- How cleanly KorE logic and markup are separated
- How the compiler identifies the boundary between logic and template
- How tooling (IDE, formatter, linter) can work with the file

We evaluate four options against a canonical example: a `Counter` component with a count state, an increment button, and a display of the current count.

---

### Option A: Script block + template block (Vue/Svelte style)

```akt
<script>
import { Subject } from "kore/process"

component Counter {
    var count: Int = 0

    fun increment() {
        assign(count = count + 1)
    }
}
</script>

<template>
    <div class="counter">
        <p>Count: {count}</p>
        <button @click="increment">Increment</button>
    </div>
</template>

<style>
.counter {
    display: flex;
    gap: 8px;
    align-items: center;
}
</style>
```

**Tradeoffs:**

The `<script>` / `<template>` boundary is explicit and familiar to Vue and Svelte developers. The parser has unambiguous boundaries. KorE code lives in one contiguous block; markup lives in another.

The problem is that this is exactly Vue's format, and it creates a false sense of familiarity — a React developer will expect JSX-style embedding, not a separate template block. The `<template>` wrapper adds syntactic noise. There is also a conceptual problem: in React, the markup is "inside" the component logic (returned from a function). Here, they are coordinate siblings. This feels wrong to React developers.

At the BEAM level: the `<script>` block defines the component's GenServer. The `<template>` block compiles to the `render/1` function. The parser splits on `<script>`, `<template>`, `<style>` tags.

**Parser complexity:** Low. The parser is a simple tag splitter followed by a KorE parser for the script block and an HTML parser for the template block.

**Assessment:** Familiar to Vue/Svelte developers. Not ideal for React developers. The mental model of markup as a "section" rather than a "return value" is a mismatch.

---

### Option B: JSX-style — markup returned from a function (React style)

```akt
import { assign } from "akt"

component Counter {
    var count: Int = 0

    fun increment() {
        assign(count = count + 1)
    }

    fun render() = <div class="counter">
        <p>Count: {count}</p>
        <button @click={::increment}>Increment</button>
    </div>
}
```

The file is pure KorE code. HTML is embedded as a first-class expression type (like JSX). The `render()` function returns markup. The file extension `.akt` signals to the compiler that HTML literal expressions are valid.

**Tradeoffs:**

This is closest to React's mental model. The markup is inside the component, returned from a function. The component is a class/object with methods. The `{::increment}` syntax for event handlers is natural KorE method reference syntax.

The challenge is parser complexity. JSX-style embedded HTML requires the KorE lexer to switch modes when it encounters `<` in an expression position, which requires lookahead to distinguish `<` as less-than from `<` as element start. This is the same problem TypeScript/Babel solve for `.tsx` files, and it is solvable — but it complicates the lexer significantly.

There is also an ergonomics issue: the `fun render() =` syntax is awkward compared to just having the markup at the end of the file. React developers are used to `return (<div>...</div>)` but not to named `render()` methods on classes.

At the BEAM level: the `component Counter` block compiles to a GenServer. The `fun render()` compiles to `render/1`. Expressions in `{}` within the markup become tracked dynamic segments.

**Parser complexity:** High. Requires context-sensitive lexing to handle `<` in expression position.

**Assessment:** Most aligned with React's mental model. Parser complexity is a real cost. The `fun render()` naming is a slight ergonomic mismatch for React developers who think in terms of "the function IS the component."

---

### Option C: Frontmatter + template (Astro style)

```akt
---
import { Button } from "./Button"

component Counter {
    var count: Int = 0

    fun increment() {
        assign(count = count + 1)
    }
}
---

<div class="counter">
    <p>Count: {count}</p>
    <Button @click="increment" label="Increment" />
</div>

<style>
.counter {
    display: flex;
    gap: 8px;
    align-items: center;
}
</style>
```

The file has a frontmatter block (delimited by `---`) containing KorE logic. Everything below the closing `---` is markup. There is no `<template>` wrapper.

**Tradeoffs:**

Astro popularized this for `.astro` files, and it has gained developer familiarity. The markup section is clean — no wrapper element required. The `---` delimiter is unambiguous and simple to parse. Imports naturally live in the frontmatter.

The weakness is that the frontmatter/template split is a purely cosmetic restatement of the Vue `<script>`/`<template>` split. It has the same conceptual problem: markup is a peer of logic, not a result of it. React developers who have used Astro will recognize it, but those who have not may find it more foreign than JSX-style.

The `component Counter { ... }` declaration in the frontmatter is redundant: the file IS the component. The component name should be derivable from the filename.

At the BEAM level: frontmatter compiles to module-level declarations and GenServer init/callbacks. The template below `---` compiles to `render/1`.

**Parser complexity:** Low. The parser splits on `---`. The frontmatter is parsed as KorE code. The template is parsed as HTML with `{}` interpolation.

**Assessment:** Clean syntax, simple parser. But the conceptual model does not map to React. Better suited to Astro-style static pages than to stateful interactive components.

---

### Option D: Fully unified — markup IS the file, logic in `{}` blocks

```akt
<div class="counter">
    <p>Count: {state.count}</p>
    <button @click={state.count += 1}>Increment</button>

    {script}
        component Counter {
            var count: Int = 0
        }
    {/script}
</div>
```

The file IS the markup. Logic lives inside `{script}` blocks embedded in the markup. This is the Svelte 5 direction pushed to an extreme.

**Tradeoffs:**

This inverts the React mental model completely. React developers think of markup as embedded in logic (the JSX return value); this makes logic embedded in markup. It is disorienting and makes complex components unreadable. It is appropriate for simple template files (like Handlebars or Mustache) but not for components with significant logic.

**Parser complexity:** Moderate. The parser treats the file as HTML with special `{script}` block handling.

**Assessment:** Wrong direction for aKt's mandate. Rejected.

---

### Recommendation: Option B (JSX-style) with filename-as-component-name and structural refinements

Option B is the right call, with two refinements that address its weaknesses:

**Refinement 1: The file IS the component.** The filename is the component name. No `component Counter { }` wrapper needed in most cases. The top-level script section of the file declares state, event handlers, and lifecycle. The trailing markup block IS the render function.

**Refinement 2: Markup block is a first-class trailing expression.** Instead of `fun render() = <div>...</div>`, the markup appears as a trailing block after the script section, separated by a blank line and the markup itself beginning with an HTML element. The compiler treats the last expression in a `.akt` file (if it is a markup literal) as the render expression.

```akt
// Counter.akt
import { assign } from "akt/core"
import { onMount } from "akt/lifecycle"

var count: Int = 0

fun increment() {
    assign { count = count + 1 }
}

fun decrement() {
    assign { count = count - 1 }
}

<div class="counter">
    <p class="count-display">Current count: {count}</p>
    <div class="controls">
        <button @click={::decrement} disabled={count <= 0}>−</button>
        <button @click={::increment}>+</button>
    </div>
</div>
```

The file has no wrapper elements for the script or template sections. KorE code at the top level is the component's logic. The trailing HTML element (and everything that follows) is the render expression. The compiler identifies the boundary: the first top-level HTML element literal starts the markup section.

The component name is derived from the filename: `Counter.akt` → `Counter` component → `'KorE.UI.Counter'` BEAM module.

For files that need explicit naming (e.g., when the filename does not match the desired export name, or for disambiguation), an optional `@Component("Name")` annotation can appear at the top of the file.

---

### Complete `.akt` File Format Reference

**Expression embedding in markup:**

```akt
var user: User? = null
var items: List<String> = emptyList()

<div>
    {/* Comment — not rendered */}
    <p>{user?.name ?: "Guest"}</p>
    <p>{"Item count: ${items.size}"}</p>
    <p>{if (user != null) "Logged in" else "Anonymous"}</p>
</div>
```

Expressions inside `{}` are KorE expressions. They are evaluated in the scope of the component's current assigns. The compiler tracks which assigns are referenced in each expression and assigns a unique diff ID to each dynamic expression site.

**Component references:**

```akt
import { Avatar } from "./Avatar"
import { UserCard } from "@components/UserCard"

var userId: Int = 0

<div>
    <Avatar src={user.avatarUrl} size={.medium} />
    <UserCard userId={userId} onSelect={::handleUserSelect} />
</div>
```

Component names are capitalized identifiers in markup. Lowercase identifiers are HTML elements. This mirrors JSX convention exactly.

**Event handler declaration:**

```akt
var value: String = ""

fun handleChange(event: InputEvent) {
    assign { value = event.target.value }
}

fun handleSubmit(event: FormEvent) {
    event.preventDefault()
    // handle submission
}

<form @submit={::handleSubmit}>
    <input
        type="text"
        value={value}
        @change={::handleChange}
    />
    <button type="submit">Submit</button>
</form>
```

`@eventName` on an HTML element is the event binding syntax. `{::handlerName}` is a KorE method reference. Inline lambdas are supported for simple cases: `@click={ assign { count = count + 1 } }`.

**Conditional rendering:**

```akt
var isLoggedIn: Boolean = false
var user: User? = null

<div>
    {if (isLoggedIn && user != null) {
        <div class="user-info">
            <p>Welcome, {user.name}</p>
            <button @click={::logout}>Logout</button>
        </div>
    } else {
        <a href="/login">Login</a>
    }}
</div>
```

Conditional rendering uses KorE's `if/else` expression inside `{}`. The branches contain markup literals.

A shorthand for simple show/hide:

```akt
<div>
    <p @if={isLoggedIn}>Welcome back</p>
    <a @unless={isLoggedIn} href="/login">Login</a>
</div>
```

`@if` and `@unless` are directive attributes — sugar that the compiler expands to the full `{if (...) { ... } else { null }}` pattern.

**List rendering:**

```akt
var items: List<TodoItem> = emptyList()

<ul>
    {items.map { item ->
        <li key={item.id}>
            <span @class={{ "completed": item.done }}>{item.title}</span>
            <button @click={ assign { items = items.toggleDone(item.id) } }>
                {if (item.done) "Undo" else "Done"}
            </button>
        </li>
    }}
</ul>
```

List rendering uses KorE's standard `map`, `filter`, `forEach` lambdas that return markup. The `key` attribute is mandatory on list items (enforced by the compiler) and must be unique within the list — it is used by the diff engine to track list element identity.

The `@class` directive accepts a Map of `String → Boolean`: classes with `true` values are applied.

---

## 11.3 — The Component Model

### Function Components (Stateless)

A function component is a `.akt` file with no state declarations, no event handlers, and no lifecycle hooks. The compiler detects this and emits a pure BEAM function rather than a GenServer.

```akt
// Button.akt
import { Atom } from "kore/atoms"

atoms { Variant { primary, secondary, danger, ghost } }
atoms { Size { small, medium, large } }

props {
    label: String
    variant: Atom<Variant> = .primary
    size: Atom<Size> = .medium
    disabled: Boolean = false
    onClick: (() -> Unit)? = null
}

<button
    class="btn btn-{variantClass(variant)} btn-{sizeClass(size)}"
    disabled={disabled}
    @click={onClick}
>
    {label}
</button>
```

```akt
// Card.akt
props {
    title: String
    subtitle: String? = null
    elevation: Int = 1
}

slots {
    default        // children
    actions        // optional action area
}

<div class="card elevation-{elevation}">
    <div class="card-header">
        <h3>{title}</h3>
        {if (subtitle != null) <p class="subtitle">{subtitle}</p>}
    </div>
    <div class="card-body">
        <slot />
    </div>
    {if (hasSlot(.actions)) {
        <div class="card-actions">
            <slot name="actions" />
        </div>
    }}
</div>
```

```akt
// Avatar.akt
atoms { Size { xs, sm, md, lg, xl } }

props {
    src: String? = null
    name: String
    size: Atom<Size> = .md
    online: Boolean = false
}

val initials: String = name.split(" ").take(2).map { it.first() }.joinToString("")

<div class="avatar avatar-{size}" aria-label={name}>
    {if (src != null) {
        <img src={src} alt={name} />
    } else {
        <span class="avatar-initials">{initials}</span>
    }}
    {if (online) <span class="online-indicator" aria-hidden="true" />}
</div>
```

Function components compile to a single BEAM function:

```erlang
%% Generated: Button.beam
-module('KorE.UI.Button').
-export([render/1]).

render(Assigns) ->
    Label = maps:get(label, Assigns),
    Variant = maps:get(variant, Assigns, primary),
    Size = maps:get(size, Assigns, medium),
    Disabled = maps:get(disabled, Assigns, false),
    [<<"<button class=\"btn btn-">>,
     variant_class(Variant), <<" btn-">>, size_class(Size), <<"\"">>,
     case Disabled of true -> <<" disabled">>; false -> <<"">> end,
     <<">">>, Label, <<"</button>">>].
```

No process is spawned. No WebSocket is allocated. The function is called inline by its parent component's render function. There is no stateful lifecycle — function components are pure functions from assigns to HTML.

**Key differences from React function components:**

- No hooks — hooks exist to manage client-side state and effects. Function components in aKt have neither.
- No re-render optimization needed — the function is called by its parent's render function, which is called when the parent's state changes. There is no concept of a "re-render" for a function component in isolation.
- No `memo()` equivalent needed — the server computes HTML; the diff engine handles optimization at the wire level.
- Props are immutable values passed from parent. There is no prop mutation, no prop drilling through context.

---

### Stateful Components

A stateful component has at least one `var` declaration (mutable assign), or uses lifecycle hooks, or declares event handlers. The compiler emits a GenServer.

```akt
// Counter.akt
import { assign } from "akt/core"
import { onMount, onDestroy } from "akt/lifecycle"

props {
    initialCount: Int = 0
    step: Int = 1
    min: Int? = null
    max: Int? = null
}

var count: Int = initialCount

onMount {
    // count is already initialized from props
    // any additional setup here
}

onDestroy {
    // cleanup
}

fun increment() {
    val newCount = count + step
    val clamped = if (max != null) minOf(newCount, max) else newCount
    assign { count = clamped }
}

fun decrement() {
    val newCount = count - step
    val clamped = if (min != null) maxOf(newCount, min) else newCount
    assign { count = clamped }
}

val atMin: Boolean = min != null && count <= min
val atMax: Boolean = max != null && count >= max

<div class="counter" aria-label="Counter: {count}">
    <button
        @click={::decrement}
        disabled={atMin}
        aria-label="Decrement by {step}"
    >−</button>
    <output class="count" aria-live="polite">{count}</output>
    <button
        @click={::increment}
        disabled={atMax}
        aria-label="Increment by {step}"
    >+</button>
</div>
```

This compiles to:

```erlang
%% Generated: Counter.beam
-module('KorE.UI.Counter').
-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         render/1, handle_event/3]).

init(Assigns) ->
    InitialCount = maps:get(initial_count, Assigns, 0),
    Step = maps:get(step, Assigns, 1),
    Min = maps:get(min, Assigns, undefined),
    Max = maps:get(max, Assigns, undefined),
    State = #{count => InitialCount, step => Step, min => Min, max => Max},
    {ok, State}.

handle_event(<<"increment">>, _Params, State) ->
    #{count := Count, step := Step, max := Max} = State,
    NewCount = Count + Step,
    Clamped = case Max of
        undefined -> NewCount;
        M -> min(NewCount, M)
    end,
    {noreply, State#{count => Clamped}};

handle_event(<<"decrement">>, _Params, State) ->
    #{count := Count, step := Step, min := Min} = State,
    NewCount = Count - Step,
    Clamped = case Min of
        undefined -> NewCount;
        M -> max(NewCount, M)
    end,
    {noreply, State#{count => Clamped}}.

render(State) ->
    #{count := Count, step := Step, min := Min, max := Max} = State,
    AtMin = Min /= undefined andalso Count =< Min,
    AtMax = Max /= undefined andalso Count >= Max,
    %% Returns diff-annotated structure, not raw iolist
    %% Omitted for brevity; see Section 11.10 for full structure
    ...
```

---

### Props System

Props are declared in a `props { }` block at the top of the `.akt` file. Each prop is a typed declaration with an optional default.

```akt
props {
    // Required props (no default)
    userId: Int
    title: String

    // Optional props with defaults
    variant: Atom<ButtonVariant> = .primary
    className: String = ""
    disabled: Boolean = false

    // Nullable props (optional with null default implied)
    subtitle: String? = null
    onClose: (() -> Unit)? = null

    // Callback props
    onSelect: ((User) -> Unit)? = null
    onError: ((Error) -> Unit)? = null
}
```

Props are immutable within the component. They are passed as initial assigns when the component mounts. A parent component cannot update a child's state by changing props after mount — to communicate updates, use events or PubSub.

**Call sites in markup:**

```akt
<UserCard
    userId={currentUser.id}
    title={currentUser.name}
    subtitle={currentUser.bio}
    onSelect={::handleUserSelect}
/>
```

The compiler validates at the call site:
- `userId` is a required prop — must be present
- `currentUser.id` must be `Int`
- `subtitle` is `String?` — `currentUser.bio: String?` is compatible
- `onSelect` expects `(User) -> Unit` — `::handleUserSelect` must have that signature

**Spread props:**

```akt
val buttonProps = ButtonProps(
    label = "Submit",
    variant = .primary,
    disabled = isLoading
)

<Button {...buttonProps} />
```

Spread props are validated at compile time if the spread expression has a known type. If the type is `Map<String, Dynamic>` (i.e., from dynamic data), spread props bypass compile-time checking and generate a runtime warning annotation.

---

### Slots (Children)

Slots are the aKt equivalent of React's `children` prop and render prop patterns.

**Default slot:**

```akt
// Panel.akt
props {
    title: String
}

slots {
    default
}

<div class="panel">
    <div class="panel-title">{title}</div>
    <div class="panel-body">
        <slot />
    </div>
</div>
```

Usage:

```akt
<Panel title="User Settings">
    <UserForm userId={user.id} />
    <DangerZone userId={user.id} />
</Panel>
```

**Named slots:**

```akt
// Modal.akt
props {
    isOpen: Boolean
    title: String
    onClose: () -> Unit
}

slots {
    default         // body content
    footer          // action buttons
}

{if (isOpen) {
    <div class="modal-overlay" @click={::handleOverlayClick}>
        <div class="modal" role="dialog" aria-modal="true" aria-labelledby="modal-title">
            <div class="modal-header">
                <h2 id="modal-title">{title}</h2>
                <button class="modal-close" @click={onClose} aria-label="Close dialog">×</button>
            </div>
            <div class="modal-body">
                <slot />
            </div>
            {if (hasSlot(.footer)) {
                <div class="modal-footer">
                    <slot name="footer" />
                </div>
            }}
        </div>
    </div>
}}
```

Usage:

```akt
<Modal isOpen={showDeleteModal} title="Confirm Delete" onClose={::closeModal}>
    <p>Are you sure you want to delete <strong>{selectedItem?.name}</strong>?</p>
    <p>This action cannot be undone.</p>

    <template slot="footer">
        <button @click={::closeModal} class="btn btn-ghost">Cancel</button>
        <button @click={::confirmDelete} class="btn btn-danger">Delete</button>
    </template>
</Modal>
```

**Scoped slots (data passed from child to parent):**

```akt
// DataTable.akt
props {
    rows: List<Map<String, Dynamic>>
    columns: List<ColumnDef>
}

slots {
    rowActions: (row: Map<String, Dynamic>) -> Markup
    emptyState
}

<table class="data-table">
    <thead>
        <tr>
            {columns.map { col -> <th key={col.key}>{col.label}</th> }}
            {if (hasSlot(.rowActions)) <th>Actions</th>}
        </tr>
    </thead>
    <tbody>
        {if (rows.isEmpty()) {
            <tr><td colspan={columns.size + 1}>
                {if (hasSlot(.emptyState)) {
                    <slot name="emptyState" />
                } else {
                    <span class="empty">No data</span>
                }}
            </td></tr>
        } else {
            rows.map { row ->
                <tr key={row["id"]}>
                    {columns.map { col ->
                        <td key={col.key}>{row[col.key]}</td>
                    }}
                    {if (hasSlot(.rowActions)) {
                        <td><slot name="rowActions" row={row} /></td>
                    }}
                </tr>
            }
        }}
    </tbody>
</table>
```

Usage:

```akt
<DataTable rows={users} columns={userColumns}>
    <template slot="rowActions" let:row={user}>
        <button @click={ assign { editingUser = user } }>Edit</button>
        <button @click={ deleteUser(user["id"] as Int) } class="btn-danger">Delete</button>
    </template>
    <template slot="emptyState">
        <p>No users found. <a href="/users/new">Create the first one.</a></p>
    </template>
</DataTable>
```

The `let:row={user}` syntax binds the scoped slot parameter (`row`) to a local name (`user`) in the parent's markup context.

---

### Component Composition

**Using components inside other components:**

Any imported `.akt` component can be used in markup as a capitalized element.

```akt
// UserProfile.akt
import { Avatar } from "./Avatar"
import { Card } from "./Card"
import { Button } from "./Button"
import { UserStats } from "./UserStats"

props {
    userId: Int
}

var user: User? = null
var isFollowing: Boolean = false

onMount {
    val loaded = UserService.getUser(userId)
    assign {
        user = loaded
        isFollowing = FollowService.isFollowing(userId)
    }
}

fun toggleFollow() {
    val newState = !isFollowing
    assign { isFollowing = newState }
    if (newState) FollowService.follow(userId)
    else FollowService.unfollow(userId)
}

{if (user != null) {
    <Card title={user.name} subtitle={user.bio}>
        <Avatar
            src={user.avatarUrl}
            name={user.name}
            size={.xl}
            online={user.isOnline}
        />
        <UserStats
            postCount={user.postCount}
            followerCount={user.followerCount}
            followingCount={user.followingCount}
        />
        <template slot="actions">
            <Button
                label={if (isFollowing) "Unfollow" else "Follow"}
                variant={if (isFollowing) .secondary else .primary}
                onClick={::toggleFollow}
            />
        </template>
    </Card>
}}
```

**Passing components as props:**

```akt
// List.akt
props {
    items: List<Dynamic>
    renderItem: (item: Dynamic, index: Int) -> Markup
    renderEmpty: (() -> Markup)? = null
}

<div class="list">
    {if (items.isEmpty()) {
        if (renderEmpty != null) renderEmpty() else <p class="empty">No items</p>
    } else {
        items.mapIndexed { index, item ->
            <div class="list-item" key={index}>
                {renderItem(item, index)}
            </div>
        }
    }}
</div>
```

The `Markup` type is a first-class type in aKt representing a markup expression value. Functions that return `Markup` can be used in `{}` interpolation sites.

---

## 11.4 — State and Lifecycle

This section is the conceptual heart of the React-to-aKt migration. React developers must understand that the mental model shift is smaller than it appears. The patterns are the same; the execution location is different.

---

### `useState` → `assign()`

**React:**

```tsx
function Counter() {
    const [count, setCount] = useState(0);
    const [name, setName] = useState("World");

    return (
        <div>
            <p>Hello, {name}! Count: {count}</p>
            <button onClick={() => setCount(c => c + 1)}>Increment</button>
        </div>
    );
}
```

State lives in the browser's React fiber tree. `setCount` schedules a re-render. React batches multiple `setCount` calls within an event handler into one render. The re-render creates a new VDOM tree and React diffs it against the previous one. The result is applied to the real DOM.

**aKt:**

```akt
var count: Int = 0
var name: String = "World"

fun increment() {
    assign { count = count + 1 }
}

<div>
    <p>Hello, {name}! Count: {count}</p>
    <button @click={::increment}>Increment</button>
</div>
```

`var` declares a mutable assign in the component's process state. `assign { }` is a block that updates one or more assigns atomically. After `assign` completes, the render function is called, a diff is computed against the previous render output, and the minimal patch is sent to the client over the WebSocket.

`assign` can update multiple assigns at once:

```akt
fun loadUser(id: Int) {
    val user = UserService.getUser(id)
    assign {
        currentUser = user
        isLoading = false
        lastLoadedAt = System.currentTimeMillis()
    }
}
```

All three assigns are updated atomically. The render function sees the fully updated state. There is no intermediate render with inconsistent state — the problem that `unstable_batchedUpdates` existed to solve in React.

**Why this is simpler than React state:**

- No stale closures. The event handler runs synchronously in the process. `count` in `increment()` is always the current value. React developers dealing with stale closures in `useEffect` and `useCallback` will find this a relief.
- No batching complexity. React 18 introduced automatic batching; before that, state updates outside event handlers were not batched. In aKt, `assign` is always atomic — there is no batching concept.
- No render loop risk. React's `useEffect` with state updates can cause infinite render loops. In aKt, `handle_event` and `handle_info` cannot trigger themselves — the process receives a message, handles it, and waits for the next one.

---

### `useEffect` → `onMount` / `handle_info`

**React `useEffect(fn, [])` (mount):**

```tsx
useEffect(() => {
    fetch('/api/user').then(r => r.json()).then(setUser);
    return () => cleanup();
}, []);
```

**aKt `onMount`:**

```akt
onMount {
    val user = UserService.getUser(userId)  // direct function call, no fetch
    assign { currentUser = user }
}

onDestroy {
    // cleanup
}
```

The key difference is already stated in the principle: `onMount` runs on the BEAM. `UserService.getUser` is a local function call. There is no `fetch`, no promise, no `.then`. The data is available synchronously within `onMount`. `assign` within `onMount` sets the initial state before the first render is sent to the client.

**React `useEffect(fn, [dep])` (dependency tracking):**

```tsx
useEffect(() => {
    const subscription = externalStore.subscribe(dep, handleChange);
    return () => subscription.unsubscribe();
}, [dep]);
```

There is no equivalent in aKt because there is no dependency tracking problem. When `dep` changes, it changes because `assign { dep = newValue }` was called in a handler. That handler can also call any side effect directly. There is no need for React's declarative effect system to bridge the gap between "state changed" and "run this code."

If a side effect needs to run when state changes, call it in the handler that changes the state:

```akt
fun updateFilter(newFilter: FilterOptions) {
    val results = SearchService.search(query, newFilter)  // runs when filter changes
    assign {
        filter = newFilter
        searchResults = results
    }
}
```

**React `useEffect` with external events → `handle_info`:**

```tsx
useEffect(() => {
    const ws = new WebSocket('ws://...');
    ws.onmessage = (event) => setMessages(m => [...m, event.data]);
    return () => ws.close();
}, []);
```

In aKt, external events arrive as BEAM messages. The component subscribes in `onMount` and receives messages via `handleInfo`:

```akt
// LiveChat.akt
import { PubSub } from "akt/pubsub"

props { roomId: String }

var messages: List<ChatMessage> = emptyList()
var users: List<User> = emptyList()

onMount {
    PubSub.subscribe("chat:room:#{roomId}")
    PubSub.subscribe("chat:presence:#{roomId}")
    val history = ChatService.getHistory(roomId, limit = 50)
    val currentUsers = PresenceService.list("chat:room:#{roomId}")
    assign {
        messages = history
        users = currentUsers
    }
}

onDestroy {
    PubSub.unsubscribe("chat:room:#{roomId}")
    PubSub.unsubscribe("chat:presence:#{roomId}")
}

handleInfo(.chatMessage) { payload: ChatMessage ->
    assign { messages = messages + payload }
}

handleInfo(.presenceUpdate) { payload: PresenceUpdate ->
    assign { users = payload.users }
}

fun sendMessage(text: String) {
    ChatService.broadcast(roomId, text)
}

<div class="chat-room">
    <div class="user-list">
        {users.map { user ->
            <div class="user" key={user.id}>{user.name}</div>
        }}
    </div>
    <div class="message-list">
        {messages.map { msg ->
            <div class="message" key={msg.id}>
                <strong>{msg.authorName}</strong>: {msg.text}
            </div>
        }}
    </div>
    <ChatInput onSend={::sendMessage} />
</div>
```

The `handleInfo` syntax takes an atom selector and a lambda with a typed payload. The compiler generates the `handle_info/2` GenServer callback. Multiple `handleInfo` blocks generate pattern-matched clauses.

---

### `useReducer` → Explicit State Machine

**React:**

```tsx
type State = 
    | { status: 'idle' }
    | { status: 'loading' }
    | { status: 'success', data: User }
    | { status: 'error', message: string };

type Action = 
    | { type: 'FETCH' }
    | { type: 'SUCCESS', payload: User }
    | { type: 'ERROR', message: string };

function reducer(state: State, action: Action): State {
    switch (action.type) {
        case 'FETCH': return { status: 'loading' };
        case 'SUCCESS': return { status: 'success', data: action.payload };
        case 'ERROR': return { status: 'error', message: action.message };
    }
}
```

**aKt with sealed class state machine:**

```akt
// UserLoader.akt
import { assign } from "akt/core"

props { userId: Int }

sealed class LoadState {
    object Idle : LoadState()
    object Loading : LoadState()
    data class Success(val user: User) : LoadState()
    data class Error(val message: String) : LoadState()
}

var loadState: LoadState = LoadState.Idle

onMount {
    assign { loadState = LoadState.Loading }
    val result = UserService.getUser(userId)
    assign {
        loadState = when (result) {
            is Ok -> LoadState.Success(result.value)
            is Err -> LoadState.Error(result.error.message)
        }
    }
}

fun retry() {
    assign { loadState = LoadState.Loading }
    val result = UserService.getUser(userId)
    assign {
        loadState = when (result) {
            is Ok -> LoadState.Success(result.value)
            is Err -> LoadState.Error(result.error.message)
        }
    }
}

{when (loadState) {
    is LoadState.Idle -> <div class="idle">Ready</div>
    is LoadState.Loading -> <div class="loading" aria-busy="true">Loading...</div>
    is LoadState.Success -> <UserCard user={loadState.user} />
    is LoadState.Error -> <div class="error" role="alert">
        <p>{loadState.message}</p>
        <button @click={::retry}>Try again</button>
    </div>
}}
```

KorE's `when` expression is the `reducer` switch statement, but it is an expression — it returns a value (here, a markup value). The sealed class hierarchy makes the state machine explicit and exhaustive. The BEAM advantage: the state cannot become inconsistent because there is one canonical copy in the process.

---

### `useContext` → PubSub / Process Messaging

React Context solves the prop-drilling problem: passing state through many layers of components that do not need it themselves. In aKt, the equivalent is PubSub for broadcast state and named process Registry for point-to-point state.

**React Context:**

```tsx
const ThemeContext = createContext<Theme>('light');

function App() {
    const [theme, setTheme] = useState<Theme>('light');
    return (
        <ThemeContext.Provider value={theme}>
            <Layout />
        </ThemeContext.Provider>
    );
}

function Button() {
    const theme = useContext(ThemeContext);
    return <button className={`btn-${theme}`}>Click</button>;
}
```

**aKt via PubSub:**

```akt
// ThemeProvider.akt — the "context provider"
import { PubSub } from "akt/pubsub"

atoms { Theme { light, dark, system } }

var theme: Atom<Theme> = .light

fun setTheme(newTheme: Atom<Theme>) {
    assign { theme = newTheme }
    PubSub.broadcast("app:theme", .themeChanged, theme)
}

<div class="theme-provider" data-theme={theme}>
    <slot />
</div>
```

```akt
// ThemedButton.akt — a "context consumer"
import { PubSub } from "akt/pubsub"

atoms { Theme { light, dark, system } }

props {
    label: String
    onClick: (() -> Unit)? = null
}

var theme: Atom<Theme> = .light

onMount {
    PubSub.subscribe("app:theme")
    theme = ThemeRegistry.current()  // read initial value from a named process
}

onDestroy {
    PubSub.unsubscribe("app:theme")
}

handleInfo(.themeChanged) { newTheme: Atom<Theme> ->
    assign { theme = newTheme }
}

<button class="btn btn-{theme}" @click={onClick}>{label}</button>
```

For simpler cases, aKt provides a `useShared` primitive backed by a named ETS table, making the pattern less verbose for global UI state (theme, locale, feature flags):

```akt
// In any component
val theme by shared<Atom<Theme>>("app:theme", default = .light)
```

`shared` creates a subscription to the named shared value. When the shared value changes (via `SharedStore.put("app:theme", .dark)`), all components holding it via `shared` receive an update automatically.

---

### `useRef` → Server vs Client Distinction

`useRef` has two uses in React that map to different aKt concepts:

**1. DOM access (`useRef` for real DOM node):**

```tsx
const inputRef = useRef<HTMLInputElement>(null);
// Later: inputRef.current.focus();
```

In aKt, DOM access requires a client-side JS hook (Section 11.5). The component declares a hook binding in markup and the hook's `mounted` callback performs the DOM operation.

```akt
// Focus input on mount via JS hook
<input type="text" phx-hook="AutoFocus" id="search-input" />
```

```javascript
// In app.js
Hooks.AutoFocus = {
    mounted() { this.el.focus(); }
};
```

**2. Mutable container without re-render (`useRef` as instance variable):**

```tsx
const timerRef = useRef<NodeJS.Timeout | null>(null);
// Does not trigger re-render when changed
```

In aKt, the process dictionary is the equivalent — mutable process-local storage that does not trigger a render:

```akt
import { processGet, processPut } from "akt/process"

onMount {
    val timerId = :timer.send_interval(1000, self(), .tick)
    processPut(:timer_id, timerId)
}

onDestroy {
    val timerId = processGet<Any>(:timer_id)
    if (timerId != null) :timer.cancel(timerId)
}
```

For most cases where React developers reach for a `useRef` container, aKt's `var` with `assign` is appropriate — the difference is that `assign` DOES trigger a render, which is usually the desired behavior. The process dictionary is only needed for truly non-reactive mutable state.

---

### `useMemo` / `useCallback`

These hooks do not exist in aKt because the problem they solve does not exist.

**Why `useMemo` exists in React:**

React re-renders a component by calling the entire function body. If the function body contains an expensive computation (e.g., sorting a large array), that computation runs on every render, even if the input has not changed. `useMemo(fn, [dep])` caches the result and only re-computes when `dep` changes.

**Why this problem does not exist in aKt:**

The component's render function (`render/1`) is called on state changes. But `render/1` is a pure function over assigns — it does not contain general KorE code. Expensive computations live in event handlers or `onMount`, where they run once in response to a specific trigger, not on every render. The render function itself should be cheap: it constructs a diff-annotated structure from current assigns.

If an expensive computation's result should be cached across renders, cache it explicitly as an assign:

```akt
var rawData: List<DataPoint> = emptyList()
var sortedData: List<DataPoint> = emptyList()  // the "memo"

handleInfo(.dataUpdate) { newData: List<DataPoint> ->
    val sorted = newData.sortedBy { it.timestamp }  // compute once, on update
    assign {
        rawData = newData
        sortedData = sorted
    }
}

<Chart data={sortedData} />
```

For truly expensive computations that need cross-request caching, ETS is the appropriate tool:

```akt
import { ETS } from "akt/ets"

fun getExpensiveResult(key: String): ComputedResult {
    return ETS.get(:component_cache, key) ?: run {
        val result = compute(key)
        ETS.put(:component_cache, key, result)
        result
    }
}
```

`useCallback` exists to stabilize function identity for `React.memo` dependency checks. Since aKt has no VDOM reconciler and no referential equality dependency tracking, `useCallback` has no equivalent and no need.

---

### Lifecycle Summary Table

| React Hook | aKt Equivalent | Notes |
|---|---|---|
| `useState(init)` | `var x: T = init` | Server-side process assign |
| `setState(fn)` | `assign { x = fn(x) }` | Atomic, synchronous on server |
| `useEffect(fn, [])` | `onMount { }` | Runs before first render, on server |
| `useEffect(() => cleanup, [])` | `onDestroy { }` | Process termination callback |
| `useEffect(fn, [dep])` | Handler that calls fn | No deps array; call side effect in the handler that updates dep |
| `useEffect(fn, [])` + WS listener | `handleInfo(.topic) { }` | BEAM message handler |
| `useReducer(reducer, init)` | `sealed class State` + `when` | Explicit state machine |
| `useContext(Ctx)` | `val x by shared<T>("key")` | PubSub-backed shared state |
| `useRef` (DOM) | JS Hook `mounted` callback | Client-side only DOM access |
| `useRef` (mutable container) | `processPut/processGet` | Process dictionary |
| `useMemo(fn, [dep])` | `var computed = …` assign | Cache in assign, update in handler |
| `useCallback(fn, [deps])` | N/A | No referential equality tracking |
| `useLayoutEffect` | N/A | Layout effects are browser-side; use JS hooks |
| `useImperativeHandle` | N/A | Component communication via events |

---

## 11.5 — Event Handling

### Basic Event Binding

Events in aKt are declared in markup using `@eventName` directive attributes. When the event fires in the browser, the event payload is serialized and sent over the WebSocket to the component's GenServer process. The GenServer calls the event handler, updates state, and the diff is pushed back.

This round-trip is typically 20–50ms over a local network connection — imperceptible for click handlers and form submissions. For interactions requiring instant visual feedback (animations, drag-and-drop), JS hooks provide client-side behavior (Section 11.5, JS Hooks).

```akt
// ClickCounter.akt
var count: Int = 0
var lastClickedAt: String = "Never"

fun handleClick(event: ClickEvent) {
    assign {
        count = count + 1
        lastClickedAt = event.timestamp.format("HH:mm:ss")
    }
}

<div class="click-counter">
    <output aria-live="polite">Clicked {count} times</output>
    <p class="timestamp">Last click: {lastClickedAt}</p>
    <button
        @click={::handleClick}
        @click.debounce={300}
    >Click me</button>
</div>
```

**Event modifiers:**

Modifiers are chained on the `@event` directive:

- `@click.prevent` — calls `preventDefault()`
- `@click.stop` — calls `stopPropagation()`
- `@submit.prevent` — most common: prevent default form submission
- `@click.debounce={300}` — debounce 300ms before sending to server
- `@input.throttle={100}` — throttle input events to max once per 100ms
- `@keydown.enter` — only trigger on Enter key
- `@keydown.escape` — only trigger on Escape key

Built-in debounce and throttle are implemented client-side — the browser holds the event and only sends to the server after the debounce window. This reduces unnecessary round-trips for rapid events (typing, scroll, resize).

---

### `handle_event` on the Component

Event handlers are KorE functions declared at the top level of a `.akt` file. The compiler validates that every `@click={::fn}` reference points to a declared function with a compatible event signature.

Event handlers receive:
- The event payload (typed based on the event type — `ClickEvent`, `InputEvent`, `FormEvent`, etc.)
- The current state is implicit — `var` assigns are accessible directly

```akt
// The function signature for various event types

fun handleClick(event: ClickEvent) { ... }          // @click
fun handleInput(event: InputEvent) { ... }          // @input, @change
fun handleSubmit(event: FormEvent) { ... }          // @submit
fun handleKeydown(event: KeyboardEvent) { ... }     // @keydown
fun handleFocus(event: FocusEvent) { ... }          // @focus, @blur

// No-argument shorthand for simple cases
fun increment() {                                   // @click — no event data needed
    assign { count = count + 1 }
}
```

The compiler generates `handle_event/3` clauses for each event handler. The event name in the generated code is the function name in snake_case: `fun handleUserSelect` → `handle_event("handle_user_select", params, state)`.

Custom event names can be specified for clarity:

```akt
@EventHandler("increment")
fun handleIncrementButton() {
    assign { count = count + 1 }
}
```

Usage in markup: `@click={event("increment")}` or the shorthand `@click="increment"`.

---

### Form Handling

```akt
// LoginForm.akt
import { FormValidator } from "akt/forms"

data class LoginFields(
    val email: String = "",
    val password: String = ""
)

var fields: LoginFields = LoginFields()
var errors: Map<String, String> = emptyMap()
var isSubmitting: Boolean = false
var submitError: String? = null

fun validateEmail(email: String): String? =
    if (!email.contains("@")) "Invalid email address" else null

fun validatePassword(password: String): String? =
    if (password.length < 8) "Password must be at least 8 characters" else null

fun handleChange(event: InputEvent) {
    val name = event.target.name
    val value = event.target.value
    val newFields = when (name) {
        "email" -> fields.copy(email = value)
        "password" -> fields.copy(password = value)
        else -> fields
    }
    val newErrors = errors.toMutableMap().apply {
        when (name) {
            "email" -> validateEmail(value)?.let { put("email", it) } ?: remove("email")
            "password" -> validatePassword(value)?.let { put("password", it) } ?: remove("password")
        }
    }
    assign {
        fields = newFields
        errors = newErrors
    }
}

fun handleSubmit(event: FormEvent) {
    event.preventDefault()
    val emailError = validateEmail(fields.email)
    val passwordError = validatePassword(fields.password)
    if (emailError != null || passwordError != null) {
        assign {
            errors = buildMap {
                emailError?.let { put("email", it) }
                passwordError?.let { put("password", it) }
            }
        }
        return
    }
    assign { isSubmitting = true; submitError = null }
    val result = AuthService.login(fields.email, fields.password)
    when (result) {
        is Ok -> redirect("/dashboard")
        is Err -> assign {
            isSubmitting = false
            submitError = result.error.message
        }
    }
}

<form @submit={::handleSubmit} novalidate>
    {if (submitError != null) {
        <div class="alert alert-error" role="alert">{submitError}</div>
    }}
    <div class="form-group" @class={{ "has-error": errors.containsKey("email") }}>
        <label for="email">Email</label>
        <input
            type="email"
            id="email"
            name="email"
            value={fields.email}
            @input={::handleChange}
            aria-invalid={errors.containsKey("email")}
            aria-describedby={if (errors.containsKey("email")) "email-error" else null}
        />
        {if (errors.containsKey("email")) {
            <span id="email-error" class="error-message">{errors["email"]}</span>
        }}
    </div>
    <div class="form-group" @class={{ "has-error": errors.containsKey("password") }}>
        <label for="password">Password</label>
        <input
            type="password"
            id="password"
            name="password"
            value={fields.password}
            @input={::handleChange}
            aria-invalid={errors.containsKey("password")}
        />
        {if (errors.containsKey("password")) {
            <span class="error-message">{errors["password"]}</span>
        }}
    </div>
    <button type="submit" disabled={isSubmitting} aria-busy={isSubmitting}>
        {if (isSubmitting) "Signing in…" else "Sign In"}
    </button>
</form>
```

The `@input.debounce={300}` modifier (not shown here, but applicable) can be added to reduce server round-trips during live validation. Live validation fires on each input event; debounce prevents excessive server calls while the user is still typing.

---

### JS Hooks for Client-Side Behavior

Some operations cannot run on the server:

- DOM focus management
- Third-party library initialization (charts, editors, pickers)
- Clipboard API access
- Animations tied to render timing
- `IntersectionObserver` / `ResizeObserver`
- `getBoundingClientRect` and other layout reads

JS hooks are JavaScript objects registered in the application's `app.js` and referenced in aKt markup via the `phx-hook` attribute (or aKt's alias `js-hook`).

**Declaring a JS hook reference in markup:**

```akt
// DatePickerInput.akt
props {
    value: String? = null
    onDateSelected: ((String) -> Unit)? = null
    minDate: String? = null
    maxDate: String? = null
}

var selectedDate: String = value ?: ""

handleInfo(.datePickerSelected) { payload: Map<String, Dynamic> ->
    val date = payload["date"] as? String ?: return
    assign { selectedDate = date }
    onDateSelected?.invoke(date)
}

fun clearDate() {
    assign { selectedDate = "" }
    jsCall("DatePicker", "clear")  // calls a named method on the JS hook
}

<div class="date-picker-wrapper">
    <input
        type="text"
        id="date-input-{componentId}"
        js-hook="DatePicker"
        js-hook-value={selectedDate}
        js-hook-min={minDate}
        js-hook-max={maxDate}
        aria-label="Select date"
        readonly
    />
    {if (selectedDate.isNotEmpty()) {
        <button @click={::clearDate} aria-label="Clear date">×</button>
    }}
    <output aria-live="polite" class="sr-only">
        {if (selectedDate.isNotEmpty()) "Selected: {selectedDate}" else "No date selected"}
    </output>
</div>
```

**The JS hook implementation:**

```javascript
// app.js
import Pikaday from 'pikaday';

Hooks.DatePicker = {
    mounted() {
        const opts = {
            field: this.el,
            minDate: this.el.dataset.hookMin ? new Date(this.el.dataset.hookMin) : undefined,
            maxDate: this.el.dataset.hookMax ? new Date(this.el.dataset.hookMax) : undefined,
            onSelect: (date) => {
                this.pushEvent("date_picker_selected", { date: date.toISOString().split('T')[0] });
            }
        };
        this.picker = new Pikaday(opts);
    },
    updated() {
        const value = this.el.dataset.hookValue;
        if (value !== this.picker.toString()) {
            this.picker.setDate(value || null, true);
        }
    },
    destroyed() {
        this.picker.destroy();
    },
    clear() {
        this.picker.setDate(null);
    }
};
```

The `js-hook-*` attributes (`js-hook-value`, `js-hook-min`, etc.) are exposed as `this.el.dataset.hook*` in the JS hook. The hook calls `this.pushEvent("date_picker_selected", payload)` to send events to the server, which arrive as `handle_info(.datePickerSelected, payload)` on the component.

`jsCall("DatePicker", "clear")` in KorE generates a Phoenix LiveView `push_event` that calls the named method on the hook instance. The compiler validates that the method name is a string literal or a compile-time constant.

---

### Optimistic Updates

For actions where latency would cause jarring UI (toggling a like button, reordering a list), optimistic updates show the result immediately while the server operation completes in the background.

```akt
// LikeButton.akt
props {
    postId: Int
    initialLiked: Boolean
    initialCount: Int
}

var isLiked: Boolean = initialLiked
var likeCount: Int = initialCount
var isPending: Boolean = false

fun toggleLike() {
    // Optimistic: update UI immediately
    val optimisticLiked = !isLiked
    val optimisticCount = if (optimisticLiked) likeCount + 1 else likeCount - 1
    assign {
        isLiked = optimisticLiked
        likeCount = optimisticCount
        isPending = true
    }

    // Server operation
    val result = PostService.toggleLike(postId)

    when (result) {
        is Ok -> assign {
            // Confirm with server's actual count (may differ if concurrent likes)
            likeCount = result.value.likeCount
            isLiked = result.value.isLiked
            isPending = false
        }
        is Err -> assign {
            // Rollback on failure
            isLiked = initialLiked
            likeCount = initialCount
            isPending = false
        }
    }
}

<button
    class="like-btn"
    @class={{ "liked": isLiked, "pending": isPending }}
    @click={::toggleLike}
    disabled={isPending}
    aria-pressed={isLiked}
    aria-label="{if (isLiked) "Unlike" else "Like"} post ({likeCount} likes)"
>
    <span class="like-icon" aria-hidden="true">{if (isLiked) "♥" else "♡"}</span>
    <span class="like-count">{likeCount}</span>
</button>
```

This works because the component process handles `toggleLike` synchronously: the optimistic update is applied, the diff is sent to the client, then the server call is made in the same process. The client sees the optimistic state immediately. When the server call completes, either the confirmation or rollback is applied and another diff is sent.

This is cleaner than React's optimistic update patterns (React Query's `onMutate`, `onError`, `onSettled`) because there is no client-side cache to manage. The server is the single source of truth; the optimistic state is a temporary assign in the process.

---

## 11.6 — Server vs Client Components

### The aKt Model

In Next.js App Router, the default is server components: components run on the server, can access server resources, but cannot hold client state. `"use client"` marks the boundary: components below it run in the browser, can hold state, can use browser APIs.

aKt's model is different and stronger: all components are stateful server processes by default. This is not Next.js's stateless server component — it is a persistent GenServer with live WebSocket connection. The component does not just render once on the server; it lives on the server for the duration of the user session.

The default is not "server at request time" but "server for the lifetime of the interaction."

---

### Server Components (Default)

Every `.akt` component without `@ClientComponent` is a server component running as a BEAM process.

Capabilities:
- Access any server resource: databases, services, file system, other processes
- Receive BEAM messages (`handle_info`)
- Subscribe to PubSub
- Access session and authentication state directly
- Full KorE type system and language features

Constraints:
- Cannot access browser APIs: `window`, `document`, `localStorage`, `navigator`
- Cannot call browser-specific JS (except via JS hooks)
- All interaction with the browser is mediated by the diff/patch WebSocket protocol

The implication is that the common Next.js pattern of "make an API call to fetch data in a server component" does not exist in aKt — you call the service or repository directly. There is no API layer needed for data that stays on the server.

---

### Client Components (`@ClientComponent`)

A `@ClientComponent` is an island of client-side JavaScript. It is compiled to JavaScript (not BEAM) and runs in the browser.

```akt
// InteractiveChart.akt
@ClientComponent
import { useState, useEffect } from "akt/client"
import { ChartJS } from "chart.js"

props {
    data: List<DataPoint>
    chartType: String = "line"
    onDataPointClick: ((DataPoint) -> Unit)? = null
}

var highlightedIndex: Int? = null

onMount {
    // Browser APIs available here
    val canvas = getElementById("chart-canvas")
    ChartJS.init(canvas, chartType, data)
}

fun handlePointClick(index: Int) {
    assign { highlightedIndex = index }
    val point = data[index]
    onDataPointClick?.invoke(point)
}

<div class="chart-container">
    <canvas id="chart-canvas" aria-label="Interactive chart" role="img" />
    {if (highlightedIndex != null) {
        <div class="tooltip">
            {data[highlightedIndex!!].let { point ->
                <span>{point.label}: {point.value}</span>
            }}
        </div>
    }}
</div>
```

A `@ClientComponent` compiles to JavaScript. The KorE-to-JS compiler handles this transformation. The server sends the initial HTML for the component when the parent server component renders. The client-side JavaScript hydrates the island and takes over interactivity.

**What `@ClientComponent` gives up:**

- Cannot access databases, services, or server processes directly
- Cannot receive BEAM messages or PubSub
- Cannot use server-only KorE APIs

**What `@ClientComponent` gains:**

- Browser APIs: DOM, `localStorage`, `navigator`, `window`, geolocation, etc.
- Client-side state that does not require a server round-trip
- Third-party JS library integration without JS hooks abstraction
- Animations driven by browser events without latency

---

### Option A: Islands Architecture (Recommended)

The server renders everything. `@ClientComponent` marks an isolated island — a subtree that is compiled to JS, sent to the browser as a script, and hydrated on the client. The rest of the page is pure server-rendered HTML with LiveView diffs.

**Architecture:**

```
Server (BEAM)
├── DashboardPage.akt (server, GenServer)
│   ├── Header.akt (server, function component)
│   ├── UserStats.akt (server, GenServer — real-time updates)
│   ├── InteractiveChart.akt (@ClientComponent — compiled to JS island)
│   └── RecentActivity.akt (server, GenServer — real-time updates)
```

The `InteractiveChart` island receives `data` as a serialized prop from the server at initial render. The server sends the chart's initial HTML. The JS bundle for `InteractiveChart` is loaded separately and hydrates just that element. Everything else is server-driven.

**JS bundle size:** Only `InteractiveChart.js` + its dependencies (Chart.js, etc.) are sent to the browser. The rest of the page has no JS bundle beyond the LiveView WebSocket client.

---

### Option B: Full Client Compilation

aKt compiles the same component to both BEAM (for server mode) and JS (for client mode). A component can run in either environment depending on context. This is React Server Components' model, extended.

This option requires a complete KorE-to-JavaScript compiler — a substantial additional compiler backend. The benefit is maximum code reuse: a `UserCard` component defined once works as a server component (no state, fast initial render) or as a client component (interactive, hydrated). The cost is compiler complexity and the risk of writing components that work in one environment but not the other (e.g., calling a database in a component accidentally deployed as a client component).

**Assessment:** Viable long-term target. Not the right initial implementation. The islands architecture delivers the most value with the least complexity at launch.

---

### Option C: Thin Client (Pure LiveView Model)

No `@ClientComponent` at all. All interactivity is server-driven. Client-side behavior is limited to JS hooks. This is Phoenix LiveView's current model.

This is the simplest implementation but does not meet aKt's design mandate. React developers expect to be able to create client-side interactive components. Prohibiting this would make aKt unsuitable for applications requiring rich client-side behavior (drag-and-drop interfaces, complex animations, third-party JS library integration beyond what hooks allow).

**Assessment:** Too restrictive for aKt's mandate. JS hooks cover the majority of cases, but `@ClientComponent` is needed for complex client-side scenarios.

---

### Recommendation

Islands architecture (`@ClientComponent` as JS islands) is the correct initial design. It aligns with aKt's core principle (server is default, client is explicit) while providing an escape hatch for browser-specific needs. The mental model maps directly to Next.js: "most things are server, mark client boundaries explicitly."

The full client compilation option (Option B) is a possible future evolution but requires a complete KorE-to-JS compiler backend. The islands model can use a simpler approach: `@ClientComponent` components compile to Kotlin/JS (leveraging Kotlin's existing Kotlin/JS compiler target) with an aKt-specific runtime shim. This avoids writing a new JS compiler while still enabling client components.

---

### The `@ClientComponent` Boundary

**What can cross the boundary:**

Props passed from server to client component must be serializable. The compiler enforces this.

Serializable types:
- `String`, `Int`, `Long`, `Double`, `Boolean`
- `List<T>` where `T` is serializable
- `Map<String, T>` where `T` is serializable
- `data class` instances where all fields are serializable
- `Atom` values (serialized as strings)
- `null`

Non-serializable types (compile error if passed as prop to `@ClientComponent`):
- `Pid`, `Subject<T>` — process identifiers cannot cross the boundary
- `() -> Unit` (function values) — cannot be serialized; use event names instead
- Any type containing a non-serializable field

**Security implications:**

The server should not pass sensitive server-only data as props to a `@ClientComponent`. Props serialized for client components are sent to the browser as part of the HTML response. The compiler does not know whether a `User` data class contains a `passwordHash` field that should never reach the client.

aKt provides a `@ServerOnly` annotation for data class fields:

```akt
data class User(
    val id: Int,
    val name: String,
    val email: String,
    @ServerOnly val passwordHash: String,   // compile error if passed to @ClientComponent
    @ServerOnly val internalNotes: String
)
```

Passing a `User` instance as a prop to a `@ClientComponent` generates a compile error if the `User` type contains any `@ServerOnly` fields. The developer must explicitly project to a client-safe type:

```akt
data class ClientUser(
    val id: Int,
    val name: String
)

// In a server component:
<UserChart user={ClientUser(id = user.id, name = user.name)} />
```

---

### Full Example: Server/Client Composition

```akt
// DashboardPage.akt (server component)
import { InteractiveChart } from "@components/InteractiveChart"
import { ActivityFeed } from "@components/ActivityFeed"
import { MetricCard } from "@components/MetricCard"

props { userId: Int }

var metrics: DashboardMetrics? = null
var chartData: List<DataPoint> = emptyList()
var isLoading: Boolean = true

onMount {
    PubSub.subscribe("user:#{userId}:metrics")
    val loaded = DashboardService.getMetrics(userId)
    val history = DashboardService.getChartData(userId, days = 30)
    assign {
        metrics = loaded
        chartData = history
        isLoading = false
    }
}

onDestroy {
    PubSub.unsubscribe("user:#{userId}:metrics")
}

handleInfo(.metricsUpdate) { updated: DashboardMetrics ->
    assign { metrics = updated }
}

fun handleChartPointSelect(point: DataPoint) {
    // Server can respond to client component events
    val detail = DashboardService.getPointDetail(point.id)
    assign { selectedPointDetail = detail }
}

var selectedPointDetail: PointDetail? = null

{if (isLoading) {
    <div class="dashboard-loading" aria-busy="true">
        <div class="skeleton" aria-label="Loading dashboard…" />
    </div>
} else if (metrics != null) {
    <div class="dashboard">
        <header class="dashboard-header">
            <h1>Dashboard</h1>
        </header>
        <div class="metrics-grid">
            <MetricCard label="Revenue" value={metrics.revenue} trend={metrics.revenueTrend} />
            <MetricCard label="Users" value={metrics.userCount} trend={metrics.userTrend} />
            <MetricCard label="Sessions" value={metrics.sessions} trend={metrics.sessionTrend} />
        </div>
        {/* @ClientComponent island — compiled to JS, hydrated in browser */}
        <InteractiveChart
            data={chartData}
            chartType="line"
            onDataPointClick={event("handle_chart_point_select")}
        />
        {/* Server component — real-time updates via PubSub */}
        <ActivityFeed userId={userId} />
        {if (selectedPointDetail != null) {
            <div class="point-detail" role="complementary">
                <h3>Detail: {selectedPointDetail.label}</h3>
                <p>{selectedPointDetail.description}</p>
            </div>
        }}
    </div>
}}
```

Note `onDataPointClick={event("handle_chart_point_select")}`: instead of passing a function reference (which cannot cross the server/client boundary), we pass an event name. The `@ClientComponent`'s `onDataPointClick` prop is `String` (an event name to push). When the client component calls `pushEvent(onDataPointClick, payload)`, the server component's `handleInfo` receives it.

---

## 11.7 — File-Based Routing

### Directory Structure

```
pages/
  index.akt                   →  GET /
  about.akt                   →  GET /about
  _layout.akt                 →  Layout wrapper for all pages in /
  _loading.akt                →  Loading state for all pages in /
  _error.akt                  →  Error boundary for all pages in /
  users/
    index.akt                 →  GET /users
    new.akt                   →  GET /users/new
    _layout.akt               →  Layout wrapper for /users/*
    [id].akt                  →  GET /users/:id
    [id]/
      edit.akt                →  GET /users/:id/edit
      posts.akt               →  GET /users/:id/posts
      posts/
        [postId].akt          →  GET /users/:id/posts/:postId
  blog/
    index.akt                 →  GET /blog
    [...slug].akt             →  GET /blog/* (catch-all)
  api/
    _layout.akt               →  (marks this subtree as REST, not LiveView)
    users.akt                 →  REST endpoint, not a component
```

---

### Integration with the Ping Router

The file-based router is a compiler feature. At build time, the compiler scans the `pages/` directory, constructs a route tree, and emits a Ping router DSL block. The developer does not write the router manually — it is generated.

Generated output for the above structure:

```kotlin
// Generated: router/pages.kt — DO NOT EDIT
router {
    pipeline(.browser) {
        plug(AKt.LiveViewPipeline)
    }

    scope("/") {
        live("/", 'KorE.Pages.Index')
        live("/about", 'KorE.Pages.About')
        live("/users", 'KorE.Pages.Users.Index')
        live("/users/new", 'KorE.Pages.Users.New')
        live("/users/:id", 'KorE.Pages.Users.Show')
        live("/users/:id/edit", 'KorE.Pages.Users.Edit')
        live("/users/:id/posts", 'KorE.Pages.Users.Posts')
        live("/users/:id/posts/:post_id", 'KorE.Pages.Users.Posts.Show')
        live("/blog", 'KorE.Pages.Blog.Index')
        live("/blog/*slug", 'KorE.Pages.Blog.CatchAll')
    }
}
```

Each `live/2` call registers a LiveView process module as the handler for that route. The Ping router handles HTTP and WebSocket upgrade. aKt handles the LiveView session within the process.

---

### Layouts

`_layout.akt` in a directory wraps all pages in that directory (and subdirectories that do not have their own layout). The layout receives a `<slot />` where the page content is inserted.

```akt
// pages/_layout.akt
import { NavBar } from "@components/NavBar"
import { Footer } from "@components/Footer"

props {
    currentUser: User?  // injected by the auth plug
}

slots { default }

<html lang="en">
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>My App</title>
        <link rel="stylesheet" href="/assets/app.css" />
        <script defer src="/assets/app.js" />
    </head>
    <body>
        <NavBar currentUser={currentUser} />
        <main id="main-content">
            <slot />
        </main>
        <Footer />
    </body>
</html>
```

```akt
// pages/users/_layout.akt
import { Breadcrumb } from "@components/Breadcrumb"
import { UserSidebar } from "@components/UserSidebar"

props {
    currentUser: User?
}

slots { default }

<div class="users-layout">
    <Breadcrumb />
    <div class="users-content">
        <UserSidebar currentUser={currentUser} />
        <div class="users-main">
            <slot />
        </div>
    </div>
</div>
```

Layouts stay alive across navigation within their scope. When the user navigates from `/users/1` to `/users/2`, the `pages/users/_layout.akt` process is not restarted — it receives a `handle_params` callback with the new params and updates its assigns. The page component is re-mounted. The layout's DOM is not re-rendered from scratch, only the diffs within the `<slot />` are patched. This is the same behavior as Next.js layouts — they persist across route changes within their directory scope.

---

### Loading States

```akt
// pages/_loading.akt
<div class="page-loading" aria-busy="true" role="status">
    <div class="spinner" aria-hidden="true" />
    <span class="sr-only">Loading page…</span>
</div>
```

The loading component is shown while the page's `onMount` is running (specifically, during the `connected` phase — the first render before `onMount` completes). Once `onMount` completes and all initial assigns are set, the page component's markup replaces the loading state.

For per-page loading states, a page can render its own loading markup conditionally:

```akt
// pages/users/[id].akt
var user: User? = null
var isLoading: Boolean = true

onMount {
    val result = UserService.getUser(id)
    assign {
        user = result.getOrNull()
        isLoading = false
    }
}

{if (isLoading) {
    <div class="user-skeleton" aria-busy="true">
        <div class="skeleton-avatar" />
        <div class="skeleton-text" />
    </div>
} else if (user != null) {
    <UserProfile user={user} />
} else {
    <NotFound resourceType="User" id={id} />
}}
```

---

### Error Boundaries

```akt
// pages/_error.akt
props {
    error: AKtError
    resetErrorBoundary: () -> Unit
}

<div class="error-boundary" role="alert">
    <h2>Something went wrong</h2>
    {if (error.isDevelopment) {
        <details class="error-details">
            <summary>Error details</summary>
            <pre>{error.message}</pre>
            <pre class="stacktrace">{error.stackTrace}</pre>
        </details>
    }}
    <button @click={resetErrorBoundary}>Try again</button>
    <a href="/">Go home</a>
</div>
```

When a page process crashes (unhandled exception), the supervisor catches the crash and renders `_error.akt` in place of the page. The error boundary receives the error information and a reset function. In development mode, full error details including stack trace are shown. In production, a sanitized message is shown. `resetErrorBoundary` restarts the page process from scratch.

---

### Dynamic Routes

Route params from `[id].akt` filename patterns are available as props:

```akt
// pages/users/[id].akt
props {
    id: Int  // from URL: /users/42 → id = 42
}

var user: User? = null

onMount {
    val result = UserService.getUser(id)
    assign { user = result.getOrNull() }
}

handleParams { params: RouteParams ->
    // Called when URL params change without full remount
    // e.g., navigating from /users/1 to /users/2 while staying in same layout
    val newId = params.get<Int>("id") ?: return
    if (newId != id) {
        val result = UserService.getUser(newId)
        assign { user = result.getOrNull() }
    }
}
```

Catch-all routes:

```akt
// pages/blog/[...slug].akt
props {
    slug: List<String>  // /blog/2024/january/my-post → ["2024", "january", "my-post"]
}

var post: BlogPost? = null
var notFound: Boolean = false

onMount {
    val path = slug.joinToString("/")
    val result = BlogService.getPostBySlug(path)
    assign {
        post = result.getOrNull()
        notFound = result is Err
    }
}

{if (notFound) {
    <NotFound message="Post not found: /{slug.joinToString("/")}" />
} else if (post != null) {
    <BlogPostView post={post} />
} else {
    <div class="loading" aria-busy="true" />
}}
```

---

### Route Guards (Auth and Redirects)

```akt
// pages/dashboard/index.akt
import { redirect } from "akt/navigation"

props {
    currentUser: User?  // injected by auth plug
}

onMount {
    if (currentUser == null) {
        redirect("/login?return_to=/dashboard")
        return  // stop further mount processing
    }
    // ... load dashboard data
}
```

`redirect` sends a redirect response before the LiveView session is established (during the initial HTTP render phase). If called during the connected WebSocket phase, it triggers a client-side navigation.

---

### Complete Blog Application Pages Directory

```
pages/
  _layout.akt          — Root layout with nav
  index.akt            — Homepage
  _loading.akt         — Root loading state
  _error.akt           — Root error boundary
  blog/
    _layout.akt        — Blog layout with sidebar
    index.akt          — Blog index (post list)
    [...slug].akt      — Individual post view
  auth/
    login.akt          — Login page
    register.akt       — Registration page
    logout.akt         — Logout action
  admin/
    _layout.akt        — Admin layout (auth-gated)
    index.akt          — Admin dashboard
    posts/
      index.akt        — Post management list
      new.akt          — New post editor
      [id]/
        edit.akt       — Edit post
        preview.akt    — Preview post
```

```akt
// pages/blog/index.akt
import { PostCard } from "@components/PostCard"
import { Pagination } from "@components/Pagination"
import { TagFilter } from "@components/TagFilter"

var posts: List<BlogPost> = emptyList()
var totalCount: Int = 0
var currentPage: Int = 1
var selectedTag: String? = null
val pageSize: Int = 10

onMount {
    loadPosts()
}

handleParams { params: RouteParams ->
    val page = params.get<Int>("page") ?: 1
    val tag = params.get<String>("tag")
    assign {
        currentPage = page
        selectedTag = tag
    }
    loadPosts()
}

fun loadPosts() {
    val result = BlogService.getPosts(
        page = currentPage,
        pageSize = pageSize,
        tag = selectedTag
    )
    assign {
        posts = result.posts
        totalCount = result.total
    }
}

fun handleTagSelect(tag: String?) {
    navigateTo("/blog", params = buildMap {
        tag?.let { put("tag", it) }
        put("page", "1")
    })
}

<div class="blog-index">
    <header class="blog-header">
        <h1>Blog</h1>
        <p>{totalCount} {if (totalCount == 1) "post" else "posts"}
            {if (selectedTag != null) " tagged \"${selectedTag}\"" else ""}
        </p>
    </header>

    <TagFilter
        selectedTag={selectedTag}
        tags={BlogService.getAllTags()}
        onSelect={::handleTagSelect}
    />

    {if (posts.isEmpty()) {
        <div class="empty-state">
            <p>No posts found{if (selectedTag != null) " with tag \"${selectedTag}\"" else ""}.</p>
        </div>
    } else {
        <div class="post-grid">
            {posts.map { post ->
                <PostCard
                    key={post.id}
                    post={post}
                    href="/blog/{post.slug}"
                />
            }}
        </div>

        <Pagination
            currentPage={currentPage}
            totalPages={(totalCount + pageSize - 1) / pageSize}
            baseUrl="/blog"
            queryParams={if (selectedTag != null) mapOf("tag" to selectedTag!!) else emptyMap()}
        />
    }}
</div>
```

---

## 11.8 — Async Data Loading

### `onMount` Data Loading (Synchronous on Server)

The most important concept to convey to React developers: when the component process is on the BEAM, calling a database or service is a local function call. There is no network between the component and the data.

```akt
// React — data fetching requires network round-trip to API
useEffect(() => {
    setLoading(true);
    fetch('/api/users')
        .then(r => r.json())
        .then(data => { setUsers(data); setLoading(false); })
        .catch(err => { setError(err.message); setLoading(false); });
}, []);
```

```akt
// aKt — calling the repository is a local function call
onMount {
    val users = UserRepository.list()  // no network, no future, no .then
    assign { this.users = users }
}
```

There is no loading state needed for synchronous `onMount` data loading. The component will not send its first render to the client until `onMount` completes. The client sees a fully loaded page on first paint.

```akt
// pages/users/index.akt
var users: List<User> = emptyList()
var stats: UserStats? = null

onMount {
    // Both calls happen synchronously; no async coordination needed
    val loadedUsers = UserRepository.list()
    val loadedStats = UserRepository.getStats()
    assign {
        users = loadedUsers
        stats = loadedStats
    }
}

<div class="users-page">
    {if (stats != null) {
        <div class="stats-bar">
            <span>{stats.total} total</span>
            <span>{stats.active} active</span>
        </div>
    }}
    <div class="users-grid">
        {users.map { user ->
            <UserCard key={user.id} user={user} />
        }}
    </div>
</div>
```

This page has no loading state. No spinner. The page does not render at all until `onMount` has fetched the data. To a browser user, the page loads fully on first paint.

---

### `assignAsync` — Non-Blocking Data Loading

For slow operations (external API calls, computationally heavy tasks), blocking `onMount` delays the initial render for all users. `assignAsync` starts the operation in a separate process and shows a loading state while it completes.

```akt
// WeatherWidget.akt
import { assignAsync } from "akt/async"

props {
    latitude: Double
    longitude: Double
}

var weather: WeatherData? = null
var weatherLoading: Boolean = true
var weatherError: String? = null

onMount {
    assignAsync(:weather_load) {
        WeatherAPI.fetch(latitude, longitude)  // external HTTP call, can be slow
    }
}

handleAsync(.weather_load) {
    onSuccess { data: WeatherData ->
        assign {
            weather = data
            weatherLoading = false
        }
    }
    onError { error ->
        assign {
            weatherError = error.message
            weatherLoading = false
        }
    }
}

fun retry() {
    assign { weatherLoading = true; weatherError = null; weather = null }
    assignAsync(:weather_load) {
        WeatherAPI.fetch(latitude, longitude)
    }
}

<div class="weather-widget" aria-live="polite">
    {when {
        weatherLoading -> <div class="loading-skeleton" aria-label="Loading weather" />
        weatherError != null -> <div class="error" role="alert">
            <p>Could not load weather: {weatherError}</p>
            <button @click={::retry}>Retry</button>
        </div>
        weather != null -> <div class="weather-data">
            <span class="temperature">{weather.temperature}°</span>
            <span class="condition">{weather.condition}</span>
            <img src={weather.iconUrl} alt={weather.condition} />
        </div>
        else -> null
    }}
</div>
```

`assignAsync(:key) { ... }` starts the block in a new supervised Task process. When it completes, it sends a message to the component process. `handleAsync(.key)` defines handlers for success and error cases. This maps directly to LiveView's `start_async/assign_async` pattern.

The `:key` atom identifies the async operation. If `assignAsync` is called again with the same key while an operation is in flight, the previous operation is cancelled. This handles the case of rapid parameter changes (e.g., typing in a search box that triggers async searches).

---

### Parallel Data Loading

```akt
// DashboardPage.akt
import { assignAsync, awaitAll } from "akt/async"

props { userId: Int }

var user: User? = null
var posts: List<Post> = emptyList()
var notifications: List<Notification> = emptyList()
var isLoading: Boolean = true

onMount {
    // Sequential — slow (each waits for previous):
    // val user = UserService.getUser(userId)
    // val posts = PostService.getUserPosts(userId)
    // val notifications = NotificationService.getUnread(userId)

    // Parallel — all three start simultaneously
    val results = awaitAll(
        async { UserService.getUser(userId) },
        async { PostService.getUserPosts(userId, limit = 5) },
        async { NotificationService.getUnread(userId) }
    )

    assign {
        user = results[0] as User?
        posts = results[1] as List<Post>
        notifications = results[2] as List<Notification>
        isLoading = false
    }
}

<div class="dashboard">
    {if (isLoading) {
        <DashboardSkeleton />
    } else {
        <div class="dashboard-content">
            {if (user != null) <UserGreeting user={user} />}
            <PostList posts={posts} />
            <NotificationList notifications={notifications} />
        </div>
    }}
</div>
```

`awaitAll` spawns multiple Task processes, waits for all to complete, and returns results in order. This is the BEAM equivalent of `Promise.all`. The dashboard loads in `max(t_user, t_posts, t_notifications)` time rather than `t_user + t_posts + t_notifications`.

For strongly typed parallel loading (avoiding `Dynamic` casts), a tuple-based API:

```akt
onMount {
    val (loadedUser, loadedPosts, loadedNotifs) = awaitAll(
        async<User> { UserService.getUser(userId) },
        async<List<Post>> { PostService.getUserPosts(userId, limit = 5) },
        async<List<Notification>> { NotificationService.getUnread(userId) }
    )
    assign {
        user = loadedUser
        posts = loadedPosts
        notifications = loadedNotifs
        isLoading = false
    }
}
```

The compiler generates the correct destructuring based on the tuple arity and type parameters.

---

### Streaming

For large lists and progressive rendering, `stream` avoids loading the entire dataset before rendering begins. Each item is appended to the DOM as it arrives.

```akt
// InfinitePostList.akt
import { stream, streamInsert, streamReset } from "akt/stream"

props { userId: Int }

// stream() declares a streamable list assign
// Items are diffed by id; only insertions/removals are sent to client
var posts: Stream<Post> = stream(domId = "post-list")
var page: Int = 1
var hasMore: Boolean = true
var isLoadingMore: Boolean = false

onMount {
    val initialPosts = PostService.getUserPosts(userId, page = 1, pageSize = 20)
    streamInsert(posts, initialPosts, at = .end)
    assign { hasMore = initialPosts.size >= 20 }
}

fun loadMore() {
    if (!hasMore || isLoadingMore) return
    assign { isLoadingMore = true; page = page + 1 }
    val morePosts = PostService.getUserPosts(userId, page = page, pageSize = 20)
    streamInsert(posts, morePosts, at = .end)
    assign {
        hasMore = morePosts.size >= 20
        isLoadingMore = false
    }
}

<div class="post-list-container">
    <ul id="post-list" phx-update="stream">
        {posts.map { post ->
            <li id="post-{post.id}" key={post.id}>
                <PostCard post={post} />
            </li>
        }}
    </ul>
    {if (hasMore) {
        <div
            class="load-more-trigger"
            js-hook="IntersectionObserver"
            js-hook-callback="loadMore"
        />
    }}
    {if (isLoadingMore) {
        <div class="loading-more" aria-busy="true">Loading more…</div>
    }}
</div>
```

`stream()` declares a diff-tracked list that uses the LiveView stream protocol. Rather than sending the full list on each update, the server sends only insertions and deletions. The `IntersectionObserver` JS hook fires a `loadMore` event when the load-more trigger scrolls into view, implementing infinite scroll without client-side list management.

---

### Server-Side Data Loading Summary for React Developers

The following table shows the React pattern and the aKt equivalent, illustrating how the complexity of client-side data fetching dissolves when the component runs on the server.

| Concern | React | aKt |
|---|---|---|
| Fetch on mount | `useEffect(() => fetch(url), [])` | `onMount { val data = Service.get() }` |
| Loading state | Manual `isLoading` state | Only needed for `assignAsync` (slow ops) |
| Error handling | `.catch` + error state | `when (result) { is Ok → … is Err → … }` |
| Cache / dedup | React Query, SWR | ETS, or not needed (call is local) |
| Parallel loading | `Promise.all([...])` | `awaitAll(async { … }, async { … })` |
| Suspense | `<Suspense>` + `use()` | `assignAsync` + `handleAsync` |
| Stale-while-revalidate | SWR library | Not needed — server has current data |
| Pagination | Manual page state + re-fetch | `handleParams` + re-call service |
| Infinite scroll | Client-side list concat | `stream()` + `streamInsert` |
| Streaming SSR | React 18 streaming | `stream()` — built into protocol |

The key insight to repeat to React developers: the libraries that constitute "data fetching" in React (React Query, SWR, Apollo, urql) exist because there is a network between the component and the data. When the component IS on the server, the problem those libraries solve mostly does not exist. The data is a function call away.

---

## 11.9 — PubSub and Real-Time

### The Model

Every stateful aKt component is a BEAM process. BEAM processes receive messages. Phoenix PubSub broadcasts messages to topics. These three facts combine to make real-time the default execution model.

A component that receives real-time updates is structurally identical to a component that handles button clicks. Both receive a message, update assigns, and push a diff to the client. The protocol is the same; the message source is different.

---

### Subscribing in `onMount`

```akt
// NotificationBell.akt
props { userId: Int }

var unreadCount: Int = 0
var notifications: List<Notification> = emptyList()

onMount {
    PubSub.subscribe("user:#{userId}:notifications")
    val initial = NotificationService.getUnread(userId)
    assign {
        unreadCount = initial.size
        notifications = initial
    }
}

onDestroy {
    PubSub.unsubscribe("user:#{userId}:notifications")
}

handleInfo(.notificationReceived) { notification: Notification ->
    assign {
        notifications = listOf(notification) + notifications
        unreadCount = unreadCount + 1
    }
}

handleInfo(.notificationsRead) { _ ->
    assign { unreadCount = 0 }
}

fun markAllRead() {
    NotificationService.markAllRead(userId)
    assign { unreadCount = 0 }
}

<div class="notification-bell" aria-live="polite">
    <button
        @click={::markAllRead}
        aria-label="{unreadCount} unread notifications"
        class="bell-button"
        @class={{ "has-unread": unreadCount > 0 }}
    >
        <span class="bell-icon" aria-hidden="true">🔔</span>
        {if (unreadCount > 0) {
            <span class="badge" aria-hidden="true">{unreadCount}</span>
        }}
    </button>
</div>
```

When a service calls `PubSub.broadcast("user:42:notifications", .notificationReceived, notification)`, every running `NotificationBell` process subscribed to that topic receives the message and updates. If the user has the app open in three browser tabs, all three tabs update simultaneously — automatically, with no client-side coordination code.

---

### Presence

Presence tracks which users are connected to a topic, with a join/leave event model. It is useful for "who's online" indicators, collaborative editing, live typing indicators, and similar features.

```akt
// LivePresence.akt
import { Presence } from "akt/presence"

props {
    roomId: String
    currentUser: User
}

var presentUsers: List<PresenceUser> = emptyList()

onMount {
    Presence.track("room:#{roomId}", currentUser.id, %{
        name: currentUser.name,
        avatarUrl: currentUser.avatarUrl,
        joinedAt: System.currentTimeMillis()
    })
    Presence.subscribe("room:#{roomId}")
    assign { presentUsers = Presence.list("room:#{roomId}") }
}

onDestroy {
    Presence.unsubscribe("room:#{roomId}")
}

handleInfo(.presenceDiff) { diff: PresenceDiff ->
    assign { presentUsers = Presence.applyDiff(presentUsers, diff) }
}

<div class="presence-list" aria-label="{presentUsers.size} users online">
    <div class="presence-avatars">
        {presentUsers.take(5).map { user ->
            <div key={user.id} class="presence-avatar" title="{user.name}">
                <img src={user.avatarUrl} alt={user.name} />
                <span class="online-dot" aria-hidden="true" />
            </div>
        }}
        {if (presentUsers.size > 5) {
            <div class="presence-overflow">+{presentUsers.size - 5}</div>
        }}
    </div>
    <span class="presence-count">
        {presentUsers.size} {if (presentUsers.size == 1) "person" else "people"} online
    </span>
</div>
```

`Presence.track` registers the current process as a presence for the topic. When the process terminates (tab closes, user navigates away), the presence is automatically removed and a `presenceDiff` is broadcast to all remaining subscribers. This is automatic — no cleanup code needed for the "user disconnected" case.

---

### Broadcasting from Services

A service or background job broadcasts to a PubSub topic. All components subscribed to that topic update.

```akt
// OrderTracker.akt — updates in real time as order status changes
props { orderId: Int }

var order: Order? = null
var statusHistory: List<StatusEvent> = emptyList()

onMount {
    PubSub.subscribe("order:#{orderId}:status")
    val loaded = OrderService.getOrder(orderId)
    assign {
        order = loaded
        statusHistory = OrderService.getStatusHistory(orderId)
    }
}

onDestroy {
    PubSub.unsubscribe("order:#{orderId}:status")
}

handleInfo(.statusUpdated) { event: StatusEvent ->
    assign {
        order = order?.copy(status = event.newStatus)
        statusHistory = statusHistory + event
    }
}

<div class="order-tracker">
    {if (order != null) {
        <div class="order-status">
            <h2>Order #{order.id}</h2>
            <div class="status-badge status-{order.status}">
                {order.status.displayName}
            </div>
        </div>
        <ol class="status-history">
            {statusHistory.map { event ->
                <li key={event.id} class="status-event">
                    <span class="event-status">{event.newStatus.displayName}</span>
                    <span class="event-time">{event.occurredAt.format("HH:mm")}</span>
                    {if (event.note != null) <p class="event-note">{event.note}</p>}
                </li>
            }}
        </ol>
    }}
</div>
```

From the order service:

```kotlin
// OrderService.kt
fun updateOrderStatus(orderId: Int, newStatus: OrderStatus, note: String? = null) {
    val event = OrderRepository.recordStatusChange(orderId, newStatus, note)
    PubSub.broadcast("order:#{orderId}:status", .statusUpdated, event)
}
```

Every `OrderTracker` component across all browser sessions watching that order updates the moment the service broadcasts. This is two lines of code in the service. There is no WebSocket infrastructure, no client-side event listener, no polling.

---

### Full Example: Collaborative Document Editor

```akt
// pages/docs/[id].akt
import { Presence } from "akt/presence"
import { PubSub } from "akt/pubsub"
import { stream, streamInsert } from "akt/stream"

props {
    id: String
    currentUser: User
}

data class DocumentChange(
    val id: String,
    val userId: Int,
    val userName: String,
    val operation: EditOperation,
    val timestamp: Long
)

var document: Document? = null
var collaborators: List<PresenceUser> = emptyList()
var changes: Stream<DocumentChange> = stream(domId = "change-log")
var isTyping: Set<Int> = emptySet()
var localContent: String = ""
var isSaving: Boolean = false

onMount {
    PubSub.subscribe("doc:#{id}:changes")
    PubSub.subscribe("doc:#{id}:typing")
    Presence.track("doc:#{id}", currentUser.id, %{
        name: currentUser.name,
        color: currentUser.assignedColor,
        avatarUrl: currentUser.avatarUrl
    })
    Presence.subscribe("doc:#{id}")

    val loaded = DocumentService.getDocument(id)
    val recentChanges = DocumentService.getRecentChanges(id, limit = 20)
    val presentUsers = Presence.list("doc:#{id}")
    streamInsert(changes, recentChanges, at = .end)
    assign {
        document = loaded
        localContent = loaded?.content ?: ""
        collaborators = presentUsers
    }
}

onDestroy {
    PubSub.unsubscribe("doc:#{id}:changes")
    PubSub.unsubscribe("doc:#{id}:typing")
    Presence.unsubscribe("doc:#{id}")
}

handleInfo(.documentChanged) { change: DocumentChange ->
    if (change.userId != currentUser.id) {
        assign { localContent = DocumentService.applyOperation(localContent, change.operation) }
    }
    streamInsert(changes, listOf(change), at = .end)
}

handleInfo(.presenceDiff) { diff: PresenceDiff ->
    assign { collaborators = Presence.applyDiff(collaborators, diff) }
}

handleInfo(.typingStarted) { payload: Map<String, Dynamic> ->
    val userId = payload["userId"] as? Int ?: return
    if (userId != currentUser.id) {
        assign { isTyping = isTyping + userId }
    }
}

handleInfo(.typingStopped) { payload: Map<String, Dynamic> ->
    val userId = payload["userId"] as? Int ?: return
    assign { isTyping = isTyping - userId }
}

fun handleContentChange(event: InputEvent) {
    val newContent = event.target.value
    assign { localContent = newContent }
    PubSub.broadcast("doc:#{id}:typing", .typingStarted, mapOf("userId" to currentUser.id))
}

fun saveDocument() {
    assign { isSaving = true }
    val result = DocumentService.save(id, localContent, currentUser.id)
    when (result) {
        is Ok -> {
            PubSub.broadcast("doc:#{id}:changes", .documentChanged, result.value)
            assign { isSaving = false; document = document?.copy(content = localContent) }
        }
        is Err -> assign { isSaving = false }
    }
}

val typingUsers: List<PresenceUser> = collaborators.filter { it.id in isTyping }

<div class="document-editor">
    <div class="editor-header">
        <h1 contenteditable={false}>{document?.title ?: "Untitled"}</h1>
        <div class="collaborators" aria-label="{collaborators.size} collaborators online">
            {collaborators.map { user ->
                <div key={user.id} class="collaborator-avatar" title="{user.name}" style="border-color: {user.color}">
                    <img src={user.avatarUrl} alt={user.name} />
                </div>
            }}
        </div>
        <button
            @click={::saveDocument}
            disabled={isSaving}
            aria-busy={isSaving}
        >
            {if (isSaving) "Saving…" else "Save"}
        </button>
    </div>

    {if (typingUsers.isNotEmpty()) {
        <div class="typing-indicator" aria-live="polite">
            {typingUsers.map { it.name }.joinToString(", ")}
            {if (typingUsers.size == 1) " is" else " are"} typing…
        </div>
    }}

    <textarea
        class="editor-content"
        value={localContent}
        @input={::handleContentChange}
        @input.debounce={500}
        aria-label="Document content"
        aria-multiline="true"
    />

    <details class="change-log">
        <summary>Change log ({changes.size} recent changes)</summary>
        <ol id="change-log" phx-update="stream">
            {changes.map { change ->
                <li id="change-{change.id}" key={change.id} class="change-entry">
                    <strong>{change.userName}</strong>
                    <span class="change-time">{change.timestamp.formatRelative()}</span>
                </li>
            }}
        </ol>
    </details>
</div>
```

This 120-line `.akt` file implements a collaborative document editor with real-time collaboration, presence tracking, typing indicators, and a streaming change log. The equivalent React implementation would require a WebSocket library, a state management solution for the collaborative state, a presence library, and significantly more client/server coordination code.

---

## 11.10 — The aKt Compiler Pipeline

### Parsing Phase

The `.akt` file format uses a two-pass parser.

**Pass 1: File structure detection**

The parser scans for the first top-level HTML element literal. Everything before it is the "script section" (KorE code). The HTML element and everything that follows is the "template section."

The boundary detection rule:
- Scan tokens at the top level (not inside brackets, parens, or braces)
- The first `<` token that begins an identifier (i.e., `<Identifier` or `<lowercase`) at the top level marks the template boundary
- Exception: `{/* comment */}` and `{if ...}` / `{when ...}` expressions before the root element are part of the template section if they appear after at least one HTML element has been encountered
- The root expression of the template must be a single HTML element or a `{...}` block containing markup

This means the following is valid — the `<div>` is the first top-level HTML element:

```akt
var x: Int = 0

fun increment() { assign { x = x + 1 } }

<div>  ← boundary: everything from here is template
    <button @click={::increment}>{x}</button>
</div>
```

**Pass 2: Section parsing**

The script section is parsed by the KorE parser as a module-level KorE source file. All standard KorE parsing applies.

The template section is parsed by the aKt markup parser:

- HTML elements: standard HTML5 parsing rules with XML-style self-closing (`<Input />` is valid)
- KorE expressions: `{expr}` where `expr` is parsed by the KorE expression parser in a special "markup expression context" that allows embedded markup literals
- Directive attributes: `@eventName`, `@if`, `@unless`, `@class`, `@style` — parsed as special attribute syntax
- Component references: capitalized tag names are component references; lowercase tag names are HTML elements
- `key` attribute: required on all list-rendered elements (compiler warning if missing)
- `id` attribute: required on all stream-rendered elements (compile error if missing)

**Markup AST:**

```
MarkupNode =
    | ElementNode(tag: String, attrs: List<Attr>, children: List<MarkupNode>)
    | ComponentNode(name: String, props: List<PropBinding>, slots: List<SlotContent>)
    | ExprNode(expr: KoreExpr)
    | TextNode(content: String)
    | ConditionalNode(cond: KoreExpr, then: MarkupNode, else: MarkupNode?)
    | ListNode(items: KoreExpr, key: KoreExpr, body: MarkupNode)
    | SlotNode(name: String?, scopeVar: String?)
    | CommentNode(content: String)
```

**Error recovery:**

The parser uses panic-mode error recovery. On encountering an unexpected token in markup:
- Emit a `KE3xxx` parse error with the location
- Skip tokens until a synchronization point (closing tag, `}`, end of file)
- Attempt to continue parsing from the synchronization point
- Errors are accumulated; parsing continues to find further errors
- Compilation fails after the parse phase if any errors are present

---

### Template Compilation

The markup AST is compiled to a render function. The render function's return type is `Rendered.t()` — Phoenix LiveView's diff-trackable structure, not a raw iolist.

**Static vs dynamic segmentation:**

The compiler walks the markup AST and classifies each node:
- **Static:** text nodes, element structure, static attribute values — these never change
- **Dynamic:** `ExprNode` and any node containing an `ExprNode` — these may change

Each dynamic expression site is assigned a unique integer ID (the "fingerprint"). The render function returns a structure mapping fingerprint IDs to their current values.

```erlang
%% Simplified generated render/1 for Counter.akt
render(Assigns) ->
    Count = maps:get(count, Assigns),
    %% Static parts are compiled to iolist constants
    %% Dynamic parts are wrapped with their fingerprint ID
    #rendered{
        static = [
            <<"<div class=\"counter\"><p>Count: ">>,
            <<"</p><div class=\"controls\">">>,
            <<"<button>−</button><button>+</button>">>,
            <<"</div></div>">>
        ],
        dynamic = #{
            0 => integer_to_binary(Count)
        }
    }.
```

On subsequent renders, the diff engine compares fingerprint 0's value. If it changed, only `integer_to_binary(Count)` is sent to the client. The client applies it to the correct DOM position identified by the fingerprint.

**Compile-time static analysis:**

The compiler records, for each assign name, which fingerprint IDs reference it. This produces an assigns-to-fingerprints mapping:

```
count → {0}
isAtMin → {1}
isAtMax → {2}
```

When `assign { count = count + 1 }` is called, the runtime knows fingerprints `{0}` must be re-evaluated. Assigns `isAtMin` and `isAtMax` are not changed — their fingerprints are not re-evaluated. This avoids full re-rendering when only one piece of state changes.

This is a compiler optimization that LiveView implements at the framework level. aKt's compiler makes the tracking explicit and verifiable at compile time.

---

### Stateful Component Compilation

A stateful `.akt` component compiles to:

```erlang
%% Generated from Counter.akt

-module('KorE.UI.Counter').
-behaviour(phoenix_live_view).
-export([mount/3, handle_params/3, handle_event/3, handle_info/2,
         render/1, terminate/2]).

%% Props with defaults → init assigns
mount(Params, _Session, Socket) ->
    InitialCount = maps:get(<<"initialCount">>, Params, 0),
    Step = maps:get(<<"step">>, Params, 1),
    Min = maps:get(<<"min">>, Params, undefined),
    Max = maps:get(<<"max">>, Params, undefined),
    Socket1 = phoenix_live_view:assign(Socket, #{
        count => InitialCount,
        step => Step,
        min => Min,
        max => Max
    }),
    {ok, Socket1}.

%% fun increment() → handle_event("increment", ...)
handle_event(<<"increment">>, _Params, Socket) ->
    #{count := Count, step := Step, max := Max} =
        phoenix_live_view:get_assign(Socket, all),
    NewCount = Count + Step,
    Clamped = case Max of
        undefined -> NewCount;
        M -> min(NewCount, M)
    end,
    {noreply, phoenix_live_view:assign(Socket, count, Clamped)};

%% fun decrement() → handle_event("decrement", ...)
handle_event(<<"decrement">>, _Params, Socket) ->
    #{count := Count, step := Step, min := Min} =
        phoenix_live_view:get_assign(Socket, all),
    NewCount = Count - Step,
    Clamped = case Min of
        undefined -> NewCount;
        M -> max(NewCount, M)
    end,
    {noreply, phoenix_live_view:assign(Socket, count, Clamped)}.

%% handleInfo blocks → handle_info/2
handle_info(_Msg, Socket) ->
    {noreply, Socket}.

%% Derived assigns (val declarations) + markup → render/1
render(Assigns) ->
    Count = maps:get(count, Assigns),
    Step = maps:get(step, Assigns),
    Min = maps:get(min, Assigns),
    Max = maps:get(max, Assigns),
    AtMin = Min /= undefined andalso Count =< Min,
    AtMax = Max /= undefined andalso Count >= Max,
    %% Diff-tracked render structure (abbreviated)
    phoenix_live_view:render(~H"""
    <div class="counter">
        <button phx-click="decrement" disabled={AtMin}>−</button>
        <output><%= Count %></output>
        <button phx-click="increment" disabled={AtMax}>+</button>
    </div>
    """, Assigns).

terminate(_Reason, _Socket) ->
    ok.
```

Note: the generated code targets Phoenix LiveView's Elixir API at the BEAM level. The KorE compiler emits Erlang Abstract Format that calls Phoenix LiveView's Erlang module. `'phoenix_live_view'` is the underlying module. This is an `@External` call at the compiler level.

---

### Function Component Compilation

A stateless `.akt` component (no `var`, no lifecycle, no event handlers) compiles to a single Erlang function:

```erlang
%% Generated from Button.akt

-module('KorE.UI.Button').
-export([render/1]).

render(Assigns) ->
    Label = maps:get(label, Assigns),
    Variant = maps:get(variant, Assigns, primary),
    Size = maps:get(size, Assigns, medium),
    Disabled = maps:get(disabled, Assigns, false),
    VariantClass = variant_class(Variant),
    SizeClass = size_class(Size),
    [<<"<button class=\"btn btn-">>, VariantClass,
     <<" btn-">>, SizeClass, <<"\"">>,
     case Disabled of
         true -> <<" disabled aria-disabled=\"true\"">>;
         false -> <<"">>
     end,
     <<" type=\"button\">">>,
     Label,
     <<"</button>">>].

variant_class(primary) -> <<"primary">>;
variant_class(secondary) -> <<"secondary">>;
variant_class(danger) -> <<"danger">>;
variant_class(ghost) -> <<"ghost">>.

size_class(small) -> <<"small">>;
size_class(medium) -> <<"medium">>;
size_class(large) -> <<"large">>.
```

Function components are inlined into their parent component's render function when the compiler can prove they are stateless. This eliminates the overhead of a function call for simple components.

---

### Language Feature Requirements for the Compiler

The `.akt` format requires these capabilities in the KorE compiler that do not exist in the base language:

**Markup expression type:** The KorE type system must include a `Markup` type. An HTML literal in a `.akt` file is an expression of type `Markup`. `Markup` values can be embedded in other markup via `{}` interpolation. Functions returning `Markup` are valid in interpolation sites.

**Two-pass parsing:** The standard KorE parser handles `.kt` files. `.akt` files require the two-pass parser described above. The compiler detects the file extension and routes to the appropriate parser.

**Template expression context:** When parsing `{}` blocks inside markup, the KorE expression parser runs in "template expression context." In this context:
- Markup literals are valid expressions
- The scope includes all declared assigns, props, `val` derived values, and imported names
- Standard KorE expressions are valid

**Prop scope in template:** Derived values (`val` declarations in the script section) are computed expressions over current assigns. They are available in the template as if they were assigns. The compiler desugars them into calls within the render function.

**Event handler type:** Event handler functions in `.akt` files have a special role. The compiler validates that functions referenced via `{::fn}` in `@event` attributes have a compatible event signature. The `handle_event/3` callback name is derived from the function name.

**`assign {}` block:** The `assign {}` block is syntactic sugar that must be understood by the compiler. It:
1. Extracts all assignment targets (`x = ...`) into `assign(socket, key, value)` calls
2. Ensures all assignments happen atomically (a single `assign/2` call with a map)
3. Tracks which assigns are updated for the diff engine

---

## 11.11 — Language Feature Requirements Inventory

This section enumerates precisely what the KorE compiler must implement to support aKt. Each item is classified by compiler phase.

---

### 1. `.akt` File Format Parser

**What it is:** A new entry point in the compiler's frontend that handles files with the `.akt` extension differently from `.kt` files.

**What it parses:** The two-pass structure: script section (standard KorE) + template section (HTML + KorE expression interpolation + directive attributes + component references).

**ASTs produced:**
- From the script section: a `KoreModuleAST` — the same AST produced by the standard KorE parser for a module
- From the template section: a `MarkupAST` — a tree of `MarkupNode` variants (see Section 11.10)
- The combined result is an `AktFileAST` containing both sub-ASTs

**Compiler phase:** Frontend — lexing/parsing. The `.akt` parser runs before the type checker and code generator.

**Error codes:** `KE3000–KE3099` for `.