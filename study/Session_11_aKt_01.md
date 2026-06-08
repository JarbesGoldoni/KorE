# Session 11: aKt — The BEAM-Native Component UI Framework

---

## 11.1 — Philosophy & Design Principles

aKt exists because of a gap. LiveView solved the right problem — stateful server-rendered UI without a JavaScript framework — but it solved it for Elixir developers. React developers look at `.heex` templates and see something unfamiliar: a template-first file where the logic lives elsewhere, where the HTML is the primary artifact and the backing module is an afterthought. That's not how React developers think. They think in components: a single file, logic and markup together, props flowing down, events bubbling up.

aKt's thesis is that you can have both. You can give React developers the single-file component model they already know, the JSX-style colocation of logic and markup, the file-based routing of Next.js, the `useState`-shaped mental model — and underneath, run it all as BEAM processes communicating over WebSocket. No Node. No hydration bundle. No Virtual DOM reconciliation on the client. One GenServer per component instance, living on the server, sending minimal HTML diffs to the browser.

### Principle 1: React DX, BEAM Execution

The surface area of aKt is designed to be recognizable to anyone who has written a React application in the last five years. The mental model of "I have state, I update state, the UI reflects state" translates directly. `useState` becomes an assignment on a server process. `useEffect` becomes `mount` and `handle_info`. `useContext` becomes PubSub. The mapping is not perfect — it cannot be, because the execution model is fundamentally different — but it is close enough that a React developer can be productive in aKt within an afternoon.

The execution model is LiveView's: a persistent WebSocket connection, server-side process per component instance, diffs sent over the wire. This is not a compromise. It is a strict upgrade for the applications where LiveView already excels: real-time UIs, collaborative tools, dashboards, forms with server-side validation. For these applications, shipping zero JavaScript for your component logic is not a limitation; it is the correct architecture.

### Principle 2: The Single-File Component is the Right Unit

LiveView's separation of `MyComponent` (the module, in `my_component.ex`) from `my_component.html.heex` (the template, in a separate file) is a reasonable choice for developers coming from MVC frameworks. Templates are separate from controllers; that's familiar. But React developers spent years arguing that separation of concerns does not mean separation of files. A button component's markup, behavior, and style are all concerns of the button. They belong together.

The `.akt` file is KorE's answer. It is a single file containing both the component logic (state declarations, lifecycle functions, event handlers) and the template. The template is not the whole file — it is a section of the file, just as the `return` statement is a section of a React function component. The logic section is valid KorE. The template section is markup with embedded KorE expressions. The compiler knows how to split them.

This is the `.tsx` model, not the `.heex` model.

### Principle 3: What Translates from Next.js

The following Next.js concepts have direct equivalents in aKt:

- **File-based routing**: `pages/users/[id].akt` becomes the route `/users/:id`. The Ping router is generated from the file structure.
- **Server Components**: The default in aKt. Components run on the server, output HTML, ship no JavaScript. This is stronger than Next.js server components because it's the *default*, not an opt-in.
- **Client Components**: Opt-in with `use client`. These are JavaScript islands embedded in server-rendered pages.
- **Layouts**: `_layout.akt` wraps all routes in a directory, composing upward to the root layout.
- **Loading states**: `_loading.akt` is shown while the page's async data loads.
- **Error boundaries**: `_error.akt` is shown when a page crashes.
- **SSR**: Everything is SSR by default. There is no "client-side navigation" that bypasses the server.
- **`getServerSideProps` equivalent**: `suspend fun loadData(params)` runs before the component mounts.

### Principle 4: What Does Not Translate

The following Next.js/React concepts have no equivalent in aKt because the execution model eliminates the need for them:

- **No Node.js**: aKt runs on the BEAM. There is no Node process, no npm build step for server components, no Webpack or Vite for the component code.
- **No hydration bundle**: Server components produce zero client JavaScript. The browser receives HTML and a WebSocket connection. There is no "rehydration" step where the client re-runs the component tree.
- **No Virtual DOM**: The server does not maintain a Virtual DOM. It maintains component state (as a GenServer state record) and a compiled render function. When state changes, the render function runs, and the diff between the previous rendered output and the new rendered output is computed on the server and sent to the client as a patch.
- **No `useEffect` for data fetching**: Data fetching happens in `mount` or `loadData`, which are server-side functions. There is no client-side fetch, no `useEffect(() => { fetch('/api/users') }, [])`.
- **No prop drilling workarounds for global state**: PubSub and process registries are the global state mechanism. There is no Redux, no Zustand, no React Context for client-side global state.

### Principle 5: The Diff Protocol as the Core Abstraction

aKt's runtime contract is precise: the server maintains a rendered tree, the client displays it, and when the server state changes the server sends the minimal patch to update the client's display. This diff is not a Virtual DOM diff — it is computed at the level of the rendered HTML string structure, using a technique first described in the Phoenix LiveView paper.

The key insight is that a template like:

```
<div class="user-card">
  <h2>{ user.name }</h2>
  <p>{ user.email }</p>
</div>
```

has two kinds of parts: static parts (`<div class="user-card"><h2>`, `</h2><p>`, `</p></div>`) that never change, and dynamic parts (`user.name`, `user.email`) that depend on state. The compiler identifies this split at compile time. The static parts are sent to the client once, on first render, and assigned numeric identifiers. Subsequently, only the dynamic values are transmitted. A state change that updates `user.name` sends a message like `{0: "Jane Doe"}` over the WebSocket, not the entire re-rendered HTML.

This is what "no Virtual DOM" means in practice: the diff is not computed by comparing two in-memory trees. It is derived from the structure of the compiled template, which the compiler has already analyzed.

---

## 11.2 — The `.akt` File Format

The `.akt` file format is the most consequential design decision in aKt. It determines what the developer experience feels like, what the compiler must do, and how readable aKt components are at scale. This section examines the design space exhaustively.

### The Structure of a `.akt` File

A `.akt` file contains two logical sections:

1. **The logic section**: Imports, type declarations, props declaration, state type, lifecycle functions, event handlers. This is valid KorE code.
2. **The template section**: Markup with embedded KorE expressions. This is the rendered output of the component.

The central design question is: how does the file indicate where the logic section ends and the template section begins?

#### Option A: `template { }` Block

The template is wrapped in an explicit `template { }` block, which appears at the end of the file (by convention) or anywhere in the file.

```kotlin
// UserCard.akt

import kore.akt.*

@Component
props UserCardProps {
    val user: User
    val showEmail: Boolean = true
}

fun formatName(user: User): String =
    "${user.firstName} ${user.lastName}"

template {
    <div class="user-card">
        <h2>{ formatName(props.user) }</h2>
        { if (props.showEmail) {
            <p class="email">{ props.user.email }</p>
        } }
    </div>
}
```

**Tradeoffs:**

The `template { }` block is unambiguous. The compiler knows exactly where the boundary is without any heuristics. It reads naturally to developers coming from Vue's single-file component format, where `<template>`, `<script>`, and `<style>` are explicit sections.

The cost is verbosity. Every component must have a `template { }` wrapper even when the component is trivially simple. The braces around the template introduce a nesting level that fights against the flat structure of markup. It is also slightly awkward that `{ }` means "KorE expression" inside the template but also wraps the entire template.

More subtly, `template { }` suggests the template is a block expression returning a value — but its semantics are different from a function body. A developer might try to declare local variables, use `return`, or write control flow at the top level of the block and be surprised by the rules.

#### Option B: `---` Separator (Astro/Svelte Style)

A `---` line (triple dash) separates the logic section (above) from the template section (below). This is the model used by Astro (where `---` separates frontmatter from the template) and is similar to Svelte's implicit boundary.

```kotlin
// UserCard.akt

import kore.akt.*

@Component
props UserCardProps {
    val user: User
    val showEmail: Boolean = true
}

fun formatName(user: User): String =
    "${user.firstName} ${user.lastName}"

---

<div class="user-card">
    <h2>{ formatName(props.user) }</h2>
    { if (props.showEmail) {
        <p class="email">{ props.user.email }</p>
    } }
</div>
```

**Tradeoffs:**

The `---` separator is visually clean. The file reads: "here is the code, here is the output." Astro developers will recognize it instantly. The template section starts at the top level of the markup — no extra nesting.

The separator is fragile in edge cases. What if `---` appears in a multiline string in the logic section? What if a markdown-rendering tool processes the file? The compiler must handle these cases carefully. The `---` also has no structural close — the template runs to end of file, which means the compiler must treat EOF as the template boundary. This is fine in practice but feels slightly asymmetric.

The biggest practical problem: syntax highlighting. A `.akt` file is not a KorE file and not an HTML file. The language server must handle the split. With `---`, the split point is a context-free token that any parser can find quickly.

#### Option C: `render()` Function (JSX Style)

The template is the return value of a `render()` function. This is the React model: a function component returns JSX from its body. In aKt, the `render()` function returns markup syntax directly.

```kotlin
// UserCard.akt

import kore.akt.*

@Component
props UserCardProps {
    val user: User
    val showEmail: Boolean = true
}

fun formatName(user: User): String =
    "${user.firstName} ${user.lastName}"

fun render(props: UserCardProps): AktNode {
    return (
        <div class="user-card">
            <h2>{ formatName(props.user) }</h2>
            { if (props.showEmail) {
                <p class="email">{ props.user.email }</p>
            } }
        </div>
    )
}
```

**Tradeoffs:**

This is the most consistent with KorE's existing syntax: the template is just KorE code. There is no special file format — a `.akt` file is a KorE file that happens to use markup syntax inside the `render()` function body. This means KorE's existing parser needs only to be extended to handle markup nodes inside expressions; the file-level structure is unchanged.

The cost is that `render()` can contain arbitrary KorE code, which blurs the boundary between "this is markup" and "this is logic." In React, this is handled by convention (put logic in hooks, not in the render function body). KorE would need the same convention, and conventions are weaker than structural boundaries.

For stateful components, the render function must have access to the current state. This requires a mechanism to expose state to `render()` — either as a parameter, as an implicit receiver, or as component-scoped variables. This is solvable but adds complexity.

The JSX model also requires that the parser recognize `(` followed by `<` as the start of a markup expression — a context-sensitive rule that complicates both parsing and syntax highlighting.

#### Recommendation: Option B (`---` Separator) with Option A (`template { }`) for Multi-Template Files

The `---` separator is the right default. It is visually clean, structurally unambiguous for the common case, and familiar to Astro/Svelte developers who are an important part of the target audience. The file reads top-to-bottom: imports and logic above, markup below.

The `template { }` block is retained for one specific use case: components that need to define multiple named templates (e.g., a component with a `template(name = "loading")` variant). In the common case (one template per file), `---` is used. If the file contains `template { }` blocks with names, the `---` separator is not used.

The `render()` approach is rejected because it undermines the structural clarity that makes `.akt` files readable at a glance. When you open a `.akt` file, you should immediately see that it is divided into logic and markup. The `render()` approach makes this a matter of convention rather than syntax.

**Final canonical `.akt` file structure:**

```kotlin
// Counter.akt

import kore.akt.*
import kore.akt.live.*

// Props declaration
props CounterProps {
    val initialCount: Int = 0
    val step: Int = 1
    val label: String = "Count"
}

// State type
data class CounterState(
    val count: Int,
    val lastUpdated: Instant?
)

// Lifecycle
fun mount(props: CounterProps): CounterState =
    CounterState(count = props.initialCount, lastUpdated = null)

// Event handlers
fun handleIncrement(state: CounterState, props: CounterProps): CounterState =
    state.copy(count = state.count + props.step, lastUpdated = Instant.now())

fun handleDecrement(state: CounterState, props: CounterProps): CounterState =
    state.copy(count = state.count - props.step, lastUpdated = Instant.now())

fun handleReset(state: CounterState): CounterState =
    state.copy(count = 0, lastUpdated = null)

---

<div class="counter" role="region" aria-label={props.label}>
    <h3>{ props.label }: { state.count }</h3>
    <div class="controls">
        <button onClick={handleDecrement} aria-label="Decrease count">−</button>
        <button onClick={handleReset} aria-label="Reset count">Reset</button>
        <button onClick={handleIncrement} aria-label="Increase count">+</button>
    </div>
    { if (state.lastUpdated != null) {
        <p class="timestamp">Last updated: { state.lastUpdated.format("HH:mm:ss") }</p>
    } }
</div>
```

### The Markup Language Inside `.akt` Files

#### HTML Elements

Standard HTML elements are written as-is. Self-closing elements follow XML syntax with `/>`:

```kotlin
---

<div class="container">
    <h1>Hello</h1>
    <p>Welcome to aKt</p>
    <input type="text" name="username" />
    <img src={user.avatarUrl} alt={user.name} />
    <br />
</div>
```

The class attribute accepts string expressions: `class="static"`, `class={dynamicClass}`, or `class={"base " + extraClass}`. There is no special class-binding syntax beyond expression interpolation; the compiler does not require it.

#### KorE Expressions

KorE expressions are embedded using `{ }` (single braces), consistent with JSX. Any KorE expression that evaluates to a renderable value may appear inside braces:

```kotlin
---

<div>
    // String interpolation
    <p>Hello, { user.name }!</p>

    // Function call
    <p>{ formatDate(order.createdAt) }</p>

    // Arithmetic
    <p>Total: ${ price * quantity }</p>

    // Method call
    <p>{ items.size } items</p>

    // Ternary via when
    <span class={ when { state.isActive -> "active"; else -> "inactive" } }>
        Status
    </span>

    // Nested component invocation
    <Avatar user={user} size={.lg} />
</div>
```

String literals inside expressions do not need escaping if they use double quotes (consistent with KorE string syntax). The `{` and `}` characters in markup that are intended as literal HTML must be written as `{"{"}` and `{"}"}` — the same convention as JSX.

#### Component Invocations

Components are invoked using PascalCase tag names. Self-closing or containing children:

```kotlin
---

<div class="page">
    // Self-closing (no children)
    <UserCard user={currentUser} />

    // With children
    <Card title="Settings">
        <SettingsForm user={currentUser} />
    </Card>

    // With multiple props
    <DataTable
        rows={tableData}
        columns={columnDefs}
        onRowClick={handleRowClick}
        loading={state.isLoading}
    />
</div>
```

The component name must resolve to a visible declaration in the `.akt` file's imports or the current package. The compiler verifies at compile time that all component invocations match their declared `props` type.

#### Conditional Rendering

Three forms are available:

**Form 1: `{if} ... {/if}` control directives** (template-level):

```kotlin
---

<div>
    {if state.isLoggedIn}
        <UserMenu user={state.user} />
    {else if state.isLoading}
        <LoadingSpinner />
    {else}
        <LoginButton />
    {/if}
</div>
```

**Form 2: Inline KorE expression** (expression-level):

```kotlin
---

<div>
    { if (state.isLoggedIn) <UserMenu user={state.user} /> else null }
</div>
```

**Form 3: `when` expression** (recommended for multi-branch):

```kotlin
---

<div>
    { when (state.status) {
        .loading -> <LoadingSpinner />
        .error   -> <ErrorMessage message={state.error} />
        .ready   -> <UserMenu user={state.user} />
    } }
</div>
```

**Recommendation**: Use `{if} ... {/if}` for block-level conditionals that span multiple elements. Use the inline `when` expression for value-level branching. Avoid the inline `if (...) expr else null` form for multi-line content — it is harder to read.

The compiler accepts all three forms. The `{if}` directive desugars to the same AST node as the inline form; they are syntactic variants, not different features.

#### List Rendering

Two forms:

**Form 1: `{for} ... {/for}` directive**:

```kotlin
---

<ul class="user-list">
    {for user in state.users}
        <li key={user.id}>
            <UserCard user={user} />
        </li>
    {/for}
</ul>
```

**Form 2: Collection expression with lambda**:

```kotlin
---

<ul class="user-list">
    { state.users.map { user ->
        <li key={user.id}>
            <UserCard user={user} />
        </li>
    } }
</ul>
```

The `key` attribute is required on the direct child of a list. The compiler emits a warning if `key` is missing. Keys must be strings or values with a stable `toString()` representation. The diff protocol uses keys to match list elements across renders; without keys, list updates produce full re-renders of the list content.

**Recommendation**: The `{for}` directive is preferred for readability in block-level list rendering. The lambda form is preferred when the collection is the result of a pipeline:

```kotlin
---

<ul>
    { state.users
        |> filter { it.isActive }
        |> sortBy { it.name }
        |> map { user -> <li key={user.id}>{ user.name }</li> }
    }
</ul>
```

#### Attribute Binding

Static attributes use bare strings. Dynamic attributes use `{ }`. Boolean attributes follow HTML semantics: `disabled={true}` renders as `disabled`, `disabled={false}` omits the attribute entirely:

```kotlin
---

<form>
    // Static attribute
    <input type="text" name="username" />

    // Dynamic attribute
    <input
        type="text"
        value={state.inputValue}
        class={"form-input " + if (state.hasError) "error" else ""}
        disabled={state.isSubmitting}
        aria-invalid={state.hasError}
        aria-describedby={ if (state.hasError) "error-msg" else null }
    />

    // Data attributes
    <div data-user-id={user.id.toString()} data-role={user.role.name} />

    // Style binding (inline styles)
    <div style={ "height: ${state.height}px; opacity: ${state.opacity}" } />
</form>
```

A `null` expression in an attribute position omits the attribute entirely. This is the standard way to conditionally include attributes: `aria-describedby={ if (hasError) "error-id" else null }`.

#### Event Binding

Events are bound by name using camelCase HTML event attribute names. The value must be a function reference or lambda:

```kotlin
fun handleClick(event: ClickEvent, state: CounterState): CounterState =
    state.copy(count = state.count + 1)

fun handleInput(event: InputEvent, state: FormState): FormState =
    state.copy(value = event.value)

---

<div>
    // Reference to declared handler (most common)
    <button onClick={handleClick}>Click me</button>

    // Lambda (for simple cases)
    <button onClick={ { _ -> state.copy(count = 0) } }>Reset</button>

    // With event data
    <input
        type="text"
        value={state.inputValue}
        onChange={handleInput}
        onBlur={handleBlur}
    />

    // Form submit
    <form onSubmit={handleSubmit}>
        ...
    </form>
</div>
```

Event handler functions have a constrained signature. The compiler verifies the signature at compile time. The standard signatures are:

```kotlin
// With event and state
fun handler(event: EventType, state: S): S

// State only (for handlers that don't need event data)
fun handler(state: S): S

// With event, state, and props
fun handler(event: EventType, state: S, props: P): S
```

The handler returns the new state. This is a pure functional style: handlers are state transition functions, not side-effecting procedures. For side effects (e.g., sending a message to another process), the return type becomes `Pair<S, List<Command>>` — covered in Section 11.5.

#### Slots and Children

The content between a component's opening and closing tags is passed as `children`:

```kotlin
// Card.akt — defines a card with a header slot and default children

props CardProps {
    val title: String
    val footer: String? = null
}

---

<div class="card">
    <div class="card-header">
        <h3>{ props.title }</h3>
    </div>
    <div class="card-body">
        { children }
    </div>
    { if (props.footer != null) {
        <div class="card-footer">{ props.footer }</div>
    } }
</div>
```

Usage:

```kotlin
---

<Card title="User Profile">
    <UserAvatar user={user} />
    <UserDetails user={user} />
</Card>
```

Named slots use the `slot` attribute on child elements:

```kotlin
// Layout.akt — named slots

---

<div class="layout">
    <header>{ slot("header") }</header>
    <main>{ children }</main>
    <aside>{ slot("sidebar") }</aside>
</div>
```

Usage:

```kotlin
---

<Layout>
    <slot name="header">
        <SiteNav />
    </slot>
    <slot name="sidebar">
        <RecentPosts />
    </slot>
    // Default children (no slot name)
    <ArticleContent article={props.article} />
</Layout>
```

Scoped slots pass data from the component back to the calling site:

```kotlin
// DataTable.akt — scoped slot for row rendering

props DataTableProps<T> {
    val rows: List<T>
    val rowKey: (T) -> String
}

---

<table>
    <tbody>
        {for row in props.rows}
            <tr key={props.rowKey(row)}>
                { slot("row", row) }
            </tr>
        {/for}
    </tbody>
</table>
```

Usage:

```kotlin
---

<DataTable rows={state.users} rowKey={ u -> u.id }>
    <slot name="row" let:row>
        <td>{ row.name }</td>
        <td>{ row.email }</td>
        <td><StatusBadge status={row.status} /></td>
    </slot>
</DataTable>
```

#### Fragments

When a component needs to return multiple root elements, use `<>...</>` (empty tag syntax, same as React) or `<Fragment>...</Fragment>`:

```kotlin
---

<>
    <dt>{ props.term }</dt>
    <dd>{ props.definition }</dd>
</>
```

Fragments produce no wrapper element in the DOM. They are the solution for list items, table rows, and other cases where an extra `<div>` wrapper would be semantically incorrect.

#### Comments

Template comments use `{/* ... */}` syntax (like JSX). These are compile-time only — they do not appear in the rendered HTML:

```kotlin
---

<div>
    {/* This is a template comment — not rendered to HTML */}
    <h1>{ props.title }</h1>

    {/* TODO: Replace with actual user data */}
    <p>Placeholder content</p>
</div>
```

HTML comments `<!-- -->` are also permitted and ARE rendered to the client HTML. Use `{/* */}` for development notes; use `<!-- -->` when you genuinely want HTML comments in output.

### The `.akt` File Compilation

When the KorE compiler encounters a `.akt` file, it performs a multi-phase compilation distinct from normal `.kore` file compilation:

**Phase 1: File splitting.** The compiler scans for the `---` separator. Everything above is the logic section; everything below is the template section. If no `---` is found, the file is rejected with a compile error: `Missing template separator (---) in .akt file`.

**Phase 2: Logic section parsing.** The logic section is parsed as normal KorE code. Imports are resolved. Props types, state types, and function declarations are type-checked. The declared event handlers are collected with their signatures.

**Phase 3: Template parsing.** The template section is parsed by the aKt template parser, producing a `TemplateAST`. The template parser is an extension of the KorE expression parser: it handles HTML element nodes, component invocation nodes, slot nodes, and embedded `{ }` expression nodes.

**Phase 4: Template type checking.** The template AST is type-checked against the logic section's declarations. Specifically:
- Every `{ expr }` node: the expression is type-checked as a KorE expression in a scope that includes `props`, `state`, and all functions declared in the logic section. The expression must evaluate to a renderable type (`String`, `Int`, `AktNode`, `List<AktNode>`, or `null`).
- Every `<ComponentName>` invocation: the component's `props` type is resolved. Each attribute is type-checked against the corresponding prop declaration. Required props without defaults that are not provided are compile errors.
- Every `onClick={handler}` binding: the handler must match one of the allowed event handler signatures for the event type.

**Phase 5: Static/dynamic split.** The compiler walks the template AST and marks every node as either static (contains no expressions that depend on `props` or `state`) or dynamic (contains at least one such expression). Static subtrees are compiled as binary string constants. This is the basis of the diff protocol optimization.

**Phase 6: Code generation.** The compiler emits Erlang Abstract Format for the component. For a stateful component (`@LiveComponent`), this includes:
- A GenServer module implementing the OTP `gen_server` behavior
- A `render/1` function that takes the current state and produces a `Rendered` data structure (a tree of static and dynamic parts)
- A `handle_event/3` function that dispatches to the declared event handlers
- A `mount/1` function
- A `update/2` function (for prop changes)
- A `terminate/2` function

**The generated BEAM modules for a component `pages/users/[id]/Profile.akt`:**

```
'KorE.Pages.Users.Id.Profile'         — the GenServer
'KorE.Pages.Users.Id.Profile.Render'  — the render function module (compiled render tree)
'KorE.Pages.Users.Id.Profile.Props'   — the props type (as a map type)
```

---

## 11.3 — The Component Model

### Stateless Function Components

A stateless component receives props and returns markup. It has no lifecycle, no state, no process. The compiler generates a simple function module, not a GenServer.

Stateless components are declared with `@Component`. By convention, they live in their own `.akt` file, but a single file may contain multiple stateless component declarations using the `component` keyword:

```kotlin
// UserCard.akt

import kore.akt.*
import myapp.domain.User

@Component
props UserCardProps {
    val user: User
    val size: AvatarSize = .medium
    val showRole: Boolean = false
    val onClick: ((User) -> Unit)? = null
}

---

<div
    class={"user-card user-card--${props.size.name}"}
    role={ if (props.onClick != null) "button" else null }
    tabIndex={ if (props.onClick != null) 0 else null }
    onClick={ if (props.onClick != null) { _ -> props.onClick!!(props.user) } else null }
>
    <Avatar
        src={props.user.avatarUrl}
        alt={props.user.name}
        size={props.size}
    />
    <div class="user-card__info">
        <span class="user-card__name">{ props.user.name }</span>
        { if (props.showRole) {
            <span class="user-card__role">{ props.user.role.displayName }</span>
        } }
    </div>
</div>
```

The generated BEAM module for a stateless component is a single function:

```erlang
%% Generated Erlang Abstract Format (illustrative)
-module('KorE.UserCard').
-export([render/1]).

render(Props) ->
    %% Static/dynamic tree representation
    #{static => [...], dynamic => [...], ...}.
```

Stateless components can be nested freely, composed inline, and passed as props. They produce no process overhead.

**Inline component declarations** (multiple components in one file):

```kotlin
// badges.akt — multiple small components in one file

@Component
props BadgeProps {
    val label: String
    val variant: BadgeVariant = .default
}

component Badge {
    <span class={"badge badge--${props.variant.name}"}>
        { props.label }
    </span>
}

@Component
props StatusDotProps {
    val online: Boolean
}

component StatusDot {
    <span
        class={"status-dot " + if (props.online) "status-dot--online" else "status-dot--offline"}
        aria-label={ if (props.online) "Online" else "Offline" }
    />
}
```

Inline `component` declarations use a block body instead of the `---` separator, since they are embedded within a larger file that may already have a primary template.

### Stateful Server Components

A stateful component is a GenServer process. Each mounted instance of the component on a connected client has a corresponding process on the server. The process holds the component's state. When state changes, the process re-runs the render function and sends the diff to the client.

Stateful components are declared with `@LiveComponent`:

```kotlin
// LiveSearch.akt

import kore.akt.*
import kore.akt.live.*
import myapp.services.SearchService

@LiveComponent
props LiveSearchProps {
    val placeholder: String = "Search..."
    val minLength: Int = 2
    val onSelect: ((SearchResult) -> Unit)? = null
}

data class LiveSearchState(
    val query: String = "",
    val results: List<SearchResult> = emptyList(),
    val loading: Boolean = false,
    val selected: SearchResult? = null
)

fun mount(props: LiveSearchProps): LiveSearchState =
    LiveSearchState()

fun handleQueryChange(event: InputEvent, state: LiveSearchState, props: LiveSearchProps): Pair<LiveSearchState, List<Command>> {
    val newQuery = event.value
    return if (newQuery.length >= props.minLength) {
        Pair(
            state.copy(query = newQuery, loading = true, results = emptyList()),
            listOf(Command.async("search") { SearchService.search(newQuery) })
        )
    } else {
        Pair(state.copy(query = newQuery, results = emptyList(), loading = false), emptyList())
    }
}

fun handleSearchResult(results: List<SearchResult>, state: LiveSearchState): LiveSearchState =
    state.copy(results = results, loading = false)

fun handleSelect(result: SearchResult, state: LiveSearchState, props: LiveSearchProps): Pair<LiveSearchState, List<Command>> {
    val commands = if (props.onSelect != null) {
        listOf(Command.callParent(props.onSelect!!, result))
    } else emptyList()
    return Pair(state.copy(selected = result, query = result.title, results = emptyList()), commands)
}

---

<div class="live-search" role="combobox" aria-expanded={state.results.isNotEmpty()}>
    <input
        type="text"
        value={state.query}
        placeholder={props.placeholder}
        onChange={handleQueryChange}
        aria-autocomplete="list"
        aria-controls="search-results"
    />
    { if (state.loading) {
        <div class="live-search__spinner" role="status" aria-label="Searching..." />
    } }
    { if (state.results.isNotEmpty()) {
        <ul id="search-results" class="live-search__results" role="listbox">
            {for result in state.results}
                <li
                    key={result.id}
                    class={"live-search__result" + if (result == state.selected) " live-search__result--selected" else ""}
                    role="option"
                    aria-selected={result == state.selected}
                    onClick={ { _ -> handleSelect(result, state, props) } }
                >
                    { result.title }
                    { if (result.subtitle != null) {
                        <span class="live-search__subtitle">{ result.subtitle }</span>
                    } }
                </li>
            {/for}
        </ul>
    } }
</div>
```

### Props System

Props are declared using the `props` keyword followed by a struct name. The struct's fields are the component's props:

```kotlin
props MyComponentProps {
    val requiredString: String              // Required, no default
    val requiredUser: User                  // Required, complex type
    val optionalInt: Int = 0                // Optional with default
    val optionalText: String? = null        // Optional nullable
    val callback: ((Event) -> Unit)? = null // Optional callback
}
```

**Required vs optional**: Props without a default value are required. The compiler verifies at every call site that required props are provided. Props with default values are optional.

**Prop validation at compile time**: The compiler type-checks every prop at every invocation site. Passing a `String` where an `Int` is expected, or omitting a required prop, is a compile error.

**Passing functions as props**: Callbacks are typed as function types. When a stateless component is called from a stateful parent, the callback is a reference to the parent's event handler.

**Spreading props**: The spread operator `...` passes all props from a value to a component invocation:

```kotlin
props ButtonProps {
    val label: String
    val variant: ButtonVariant = .primary
    val disabled: Boolean = false
    val onClick: () -> Unit
}

---

// When wrapping a component, spread its props through
<div class="button-wrapper">
    <Button ...{props} />
</div>
```

The spread operator is checked by the compiler: the spread value must be assignment-compatible with the target component's props type. Spreading a type that has fields the target doesn't accept is a compile error unless the target has a `vararg` props declaration (see below).

**Computed prop defaults**: Default values can reference other props using `by`:

```kotlin
props AvatarProps {
    val user: User
    val alt: String by { props.user.name }  // Computed default
    val size: Int = 40
}
```

### Children and Slots

Children are typed as `AktNode` (a single node) or `List<AktNode>` (multiple children). The `children` binding is automatically available in the template:

```kotlin
props PanelProps {
    val title: String
    val collapsible: Boolean = false
}

data class PanelState(val collapsed: Boolean = false)

fun mount(props: PanelProps): PanelState = PanelState()
fun handleToggle(state: PanelState): PanelState = state.copy(collapsed = !state.collapsed)

---

<div class={"panel" + if (state.collapsed) " panel--collapsed" else ""}>
    <div class="panel__header">
        <h3>{ props.title }</h3>
        { if (props.collapsible) {
            <button
                onClick={handleToggle}
                aria-expanded={!state.collapsed}
                aria-label={ if (state.collapsed) "Expand panel" else "Collapse panel" }
            >
                { if (state.collapsed) "▶" else "▼" }
            </button>
        } }
    </div>
    { if (!state.collapsed) {
        <div class="panel__body">{ children }</div>
    } }
</div>
```

Named slots:

```kotlin
// AppLayout.akt

---

<div class="app-layout">
    <nav class="app-layout__nav">
        { slot("nav") ?: <DefaultNav /> }
    </nav>
    <main class="app-layout__main">
        { children }
    </main>
    <footer class="app-layout__footer">
        { slot("footer") ?: <DefaultFooter /> }
    </footer>
</div>
```

Usage:

```kotlin
---

<AppLayout>
    <slot name="nav">
        <CustomNav currentUser={state.user} />
    </slot>

    <ArticlePage article={state.article} />

    <slot name="footer">
        <ArticleFooter author={state.article.author} />
    </slot>
</AppLayout>
```

### Component Composition

Stateless components compose by nesting: the outer component's render function evaluates the inner component's render function and splices in the result.

Stateful components compose differently. A `@LiveComponent` embedded inside another `@LiveComponent`'s template creates a child process. The parent process does not directly call the child's render function — it sends the child's props to the child process, which runs its own render cycle and sends its own diffs to the client. The diffs are merged by the client runtime.

This means stateful component composition is **process composition**: each stateful component in the tree is an independent GenServer. Communication between parent and child uses commands:

```kotlin
// Parent to child: via props (normal)
<ChildComponent value={state.someValue} />

// Child to parent: via callback prop
fun handleChildEvent(result: ChildResult, state: ParentState): ParentState =
    state.copy(childResult = result)

// In template:
<ChildComponent onResult={handleChildEvent} />
```

For more complex communication, parent and child can communicate via PubSub or via process registry lookup — the same mechanisms any two BEAM processes would use.

---

## 11.4 — State and Lifecycle

aKt's state and lifecycle model is a translation of React's hook model into the BEAM process model. This section maps each React hook to its aKt equivalent precisely.

### `useState` → Component State

React:

```tsx
const [count, setCount] = useState(0)
const [user, setUser] = useState<User | null>(null)

setCount(prev => prev + 1)
setUser({ name: "Alice" })
```

aKt: State is a single typed value held in the component's GenServer process. There is no `useState` call — state is declared as a `data class`, initialized in `mount`, and updated by returning a new value from event handlers.

```kotlin
// State declaration
data class MyState(
    val count: Int = 0,
    val user: User? = null
)

// Initialization (equivalent to useState initial value)
fun mount(props: MyProps): MyState = MyState(count = props.initialCount)

// Update (equivalent to setCount / setUser)
fun handleIncrement(state: MyState): MyState =
    state.copy(count = state.count + 1)

fun handleSetUser(user: User, state: MyState): MyState =
    state.copy(user = user)
```

The key difference: React state updates are independent per `useState` call. aKt state is a single value — the whole state record is replaced on every update. `data class` with `copy()` provides the ergonomics of partial update. If managing multiple independent pieces of state feels cumbersome, that is a signal to split the component.

### `useEffect` → `mount`, `handle_info`, `terminate`

**`useEffect(() => {}, [])` — runs once on mount:**

React:

```tsx
useEffect(() => {
    analytics.track("page_view", { page: "dashboard" })
    subscribeToUpdates(userId)
}, [])
```

aKt: `mount` is the equivalent. It runs when the component's process is started (the first render):

```kotlin
fun mount(props: DashboardProps): Pair<DashboardState, List<Command>> {
    return Pair(
        DashboardState(),
        listOf(
            Command.run { Analytics.track(.pageView, mapOf("page" to "dashboard")) },
            Command.subscribe("updates:${props.userId}")
        )
    )
}
```

When `mount` needs to return commands (side effects), it returns `Pair<State, List<Command>>` instead of just `State`. When it needs no side effects, it returns `State` directly.

**`useEffect(() => {}, [dep])` — runs when dependency changes:**

React:

```tsx
useEffect(() => {
    fetchUserPosts(userId)
}, [userId])
```

aKt: There is no reactive dependency tracking. Instead, this pattern is handled by `update`, which is called when the component's props change:

```kotlin
// 'update' is called when props change — equivalent to useEffect with [dep]
fun update(newProps: PostListProps, oldProps: PostListProps, state: PostListState): Pair<PostListState, List<Command>> {
    return if (newProps.userId != oldProps.userId) {
        Pair(
            state.copy(posts = emptyList(), loading = true),
            listOf(Command.async("fetch_posts") { PostService.getUserPosts(newProps.userId) })
        )
    } else {
        Pair(state, emptyList())
    }
}
```

If the "dependency" is an internal state value (not a prop), the pattern is different: trigger the effect directly from the state transition that changes the value, rather than observing the change reactively.

**`useEffect(() => { return cleanup }, [])` — cleanup on unmount:**

React:

```tsx
useEffect(() => {
    const sub = subscribeToUpdates(userId)
    return () => sub.unsubscribe()
}, [])
```

aKt: `terminate` is called when the component's process is stopped (the client disconnects or navigates away):

```kotlin
fun mount(props: FeedProps): Pair<FeedState, List<Command>> =
    Pair(FeedState(), listOf(Command.subscribe("feed:${props.userId}")))

fun terminate(state: FeedState, props: FeedProps): Unit {
    // Cleanup runs here — Command.subscribe automatically unsubscribes on terminate
    // Explicit cleanup for custom resources:
    ConnectionPool.release(state.connection)
}
```

`Command.subscribe` handles its own cleanup automatically — the subscription is removed when the process stops. Explicit `terminate` is needed only for resources that require manual cleanup beyond what `Command` lifecycle management handles.

### `useReducer` → Explicit State Machine

React:

```tsx
type Action = { type: 'increment' } | { type: 'decrement' } | { type: 'reset' }

function reducer(state: CounterState, action: Action): CounterState {
    switch (action.type) {
        case 'increment': return { count: state.count + 1 }
        case 'decrement': return { count: state.count - 1 }
        case 'reset':     return { count: 0 }
    }
}

const [state, dispatch] = useReducer(reducer, { count: 0 })
dispatch({ type: 'increment' })
```

aKt: `useReducer` is not needed as a distinct construct. The event handler functions collectively ARE the reducer. Each event handler is a state transition function. The "action type" discrimination is done at the routing level (which function is called) rather than inside a single `when` block.

For complex state machines where the reducer pattern is genuinely useful, use a sealed class and a single `reduce` function:

```kotlin
sealed class CounterEvent {
    object Increment : CounterEvent()
    object Decrement : CounterEvent()
    data class Reset(val to: Int = 0) : CounterEvent()
    data class SetStep(val step: Int) : CounterEvent()
}

data class CounterState(val count: Int, val step: Int = 1)

fun reduce(event: CounterEvent, state: CounterState): CounterState = when (event) {
    is CounterEvent.Increment -> state.copy(count = state.count + state.step)
    is CounterEvent.Decrement -> state.copy(count = state.count - state.step)
    is CounterEvent.Reset     -> state.copy(count = event.to)
    is CounterEvent.SetStep   -> state.copy(step = event.step)
}

// Event handlers delegate to the reducer
fun handleIncrement(state: CounterState) = reduce(CounterEvent.Increment, state)
fun handleDecrement(state: CounterState) = reduce(CounterEvent.Decrement, state)
fun handleReset(state: CounterState)     = reduce(CounterEvent.Reset(), state)
```

### `useContext` → PubSub and Process Registry

React:

```tsx
const ThemeContext = createContext<Theme>('light')

// Provider
<ThemeContext.Provider value={theme}>
    <App />
</ThemeContext.Provider>

// Consumer
const theme = useContext(ThemeContext)
```

aKt: `useContext` has two use cases: passing data down a tree without prop drilling, and accessing "global" application state. Both have BEAM-native equivalents.

**For tree-scoped shared data (equivalent to Provider/Consumer):** The recommended pattern is to pass the data as props through the tree. aKt does not have a client-side context API because the rendering model is server-side — there is no in-memory component tree that context can traverse. If prop drilling is painful, consider whether the data should be fetched directly in each component that needs it (components have their own processes; the fetch cost is negligible), or whether it should come through the routing/layout system.

**For application-wide global state:** PubSub is the mechanism:

```kotlin
// In mount — subscribe to theme changes
fun mount(props: ThemedComponentProps): Pair<ThemedState, List<Command>> =
    Pair(
        ThemedState(theme = ThemeRegistry.current()),
        listOf(Command.subscribe("theme:changes"))
    )

// In handle_info — receive theme change messages
fun handle_info(msg: ThemeChanged, state: ThemedState): ThemedState =
    state.copy(theme = msg.newTheme)
```

**For per-session data (current user, auth token, locale):** These are passed through the router as part of the session context, accessible in `mount`:

```kotlin
fun mount(props: MyProps, session: Session): Pair<MyState, List<Command>> {
    val currentUser = session.get<User>("current_user")
    return Pair(MyState(currentUser = currentUser), emptyList())
}
```

### `useRef` → JS Hook Handle

React:

```tsx
const inputRef = useRef<HTMLInputElement>(null)
inputRef.current?.focus()
```

aKt: `useRef` is not directly applicable in the server-rendered model because the server does not have a reference to DOM elements. For cases where you need to imperatively interact with a DOM element, the `use:` directive and JS hooks are the mechanism (covered in Section 11.11).

For the common focus-management use case:

```kotlin
---

// Server-side: declare the element with a ref id
<input
    type="text"
    use:focus={state.shouldFocus}  // Triggers focus via JS hook when true
    value={state.value}
    onChange={handleChange}
/>
```

For storing mutable server-side references across renders (the other common `useRef` use case), store the value in the component's state record. Unlike in React, storing a value in state that does not affect rendering does not cause performance problems — the compiler's static/dynamic split ensures that state fields unused in the template do not trigger diff work.

### `useMemo` / `useCallback` → Computed Values and Module Functions

React:

```tsx
const sortedUsers = useMemo(() =>
    [...users].sort((a, b) => a.name.localeCompare(b.name)),
    [users]
)

const handleClick = useCallback((id: string) => {
    dispatch({ type: 'select', id })
}, [dispatch])
```

aKt: `useMemo` is unnecessary. Functions called in the template are pure KorE functions — the compiler can inline them and the BEAM's garbage collector handles the output efficiently. There is no need to memoize to prevent re-renders because there is no Virtual DOM reconciliation; the diff protocol only sends changed dynamic values.

```kotlin
// No useMemo needed — this is called on every render, and that's fine
fun sortedUsers(state: UserListState): List<User> =
    state.users.sortedBy { it.name }

---

<ul>
    {for user in sortedUsers(state)}
        <li key={user.id}>{ user.name }</li>
    {/for}
</ul>
```

If the sort is genuinely expensive (thousands of items), store the sorted list in state and update it only when the source list changes:

```kotlin
fun handleUsersLoaded(users: List<User>, state: UserListState): UserListState =
    state.copy(
        users = users,
        sortedUsers = users.sortedBy { it.name }  // Computed once on update
    )
```

`useCallback` is not needed because function references in event handlers are resolved at compile time; they are not closures that need to be stabilized to prevent re-renders.

### `useTransition` → `assign_async` Equivalent

React:

```tsx
const [isPending, startTransition] = useTransition()

startTransition(() => {
    setTab(nextTab)
})
```

aKt: Async state updates use the `Command.async` mechanism:

```kotlin
fun handleTabChange(tab: Tab, state: PageState): Pair<PageState, List<Command>> =
    Pair(
        state.copy(activeTab = tab, loading = true),
        listOf(Command.async("load_tab_data") { TabService.loadData(tab) })
    )

fun handleTabDataLoaded(result: Ok<TabData>, state: PageState): PageState =
    state.copy(tabData = result.value, loading = false)

fun handleTabDataError(result: Err<String>, state: PageState): PageState =
    state.copy(error = result.error, loading = false)
```

The `Command.async` system is covered fully in Section 11.8.

### Complete Lifecycle Diagram

```
Client connects
      │
      ▼
  loadData(params)    ← Page-level data loading (like getServerSideProps)
      │
      ▼
  mount(props)        ← Component process starts, initial state set
      │               ← Side effects via Command list
      ▼
  render(state)       ← Template evaluated, diff tree produced
      │               ← Initial HTML sent to client
      ▼
  ┌─────────────────────────────────────────────────────┐
  │                 Component Running                   │
  │                                                     │
  │  User event → handle_event → new state → render     │
  │  Async result → handle_info → new state → render    │
  │  Props change → update → new state → render         │
  │                                                     │
  └─────────────────────────────────────────────────────┘
      │
      ▼
  terminate(state)    ← Client disconnects or navigates
                      ← Cleanup runs here
```

**Complete lifecycle example:**

```kotlin
// RealtimeFeed.akt

import kore.akt.*
import kore.akt.live.*
import myapp.services.{PostService, PubSub}
import myapp.domain.{Post, User}

@LiveComponent
props RealtimeFeedProps {
    val userId: String
    val initialLimit: Int = 20
}

data class FeedState(
    val posts: List<Post> = emptyList(),
    val loading: Boolean = true,
    val error: String? = null,
    val newPostCount: Int = 0,
    val limit: Int = 20
)

// LIFECYCLE: mount — equivalent to componentDidMount + initial render
fun mount(props: RealtimeFeedProps): Pair<FeedState, List<Command>> =
    Pair(
        FeedState(limit = props.initialLimit),
        listOf(
            Command.async("load_posts") { PostService.getRecent(props.userId, props.initialLimit) },
            Command.subscribe("feed:${props.userId}")
        )
    )

// LIFECYCLE: handle_info — receives async results and PubSub messages
fun handle_info(msg: AsyncResult<"load_posts", List<Post>>, state: FeedState): FeedState =
    when (msg) {
        is Ok -> state.copy(posts = msg.value, loading = false)
        is Err -> state.copy(error = msg.reason.toString(), loading = false)
    }

fun handle_info(msg: NewPost, state: FeedState): FeedState =
    state.copy(newPostCount = state.newPostCount + 1)

// LIFECYCLE: update — equivalent to componentDidUpdate / useEffect([dep])
fun update(newProps: RealtimeFeedProps, oldProps: RealtimeFeedProps, state: FeedState): Pair<FeedState, List<Command>> =
    if (newProps.userId != oldProps.userId) {
        Pair(
            FeedState(loading = true, limit = newProps.initialLimit),
            listOf(
                Command.unsubscribe("feed:${oldProps.userId}"),
                Command.async("load_posts") { PostService.getRecent(newProps.userId, newProps.initialLimit) },
                Command.subscribe("feed:${newProps.userId}")
            )
        )
    } else {
        Pair(state, emptyList())
    }

// LIFECYCLE: terminate — cleanup
fun terminate(state: FeedState, props: RealtimeFeedProps): Unit {
    PostService.recordLastViewed(props.userId, state.posts.firstOrNull()?.id)
}

// EVENT HANDLERS
fun handleLoadNew(state: FeedState, props: RealtimeFeedProps): Pair<FeedState, List<Command>> =
    Pair(
        state.copy(loading = true, newPostCount = 0),
        listOf(Command.async("load_posts") { PostService.getRecent(props.userId, state.limit) })
    )

fun handleLoadMore(state: FeedState, props: RealtimeFeedProps): Pair<FeedState, List<Command>> {
    val newLimit = state.limit + props.initialLimit
    return Pair(
        state.copy(loading = true, limit = newLimit),
        listOf(Command.async("load_posts") { PostService.getRecent(props.userId, newLimit) })
    )
}

---

<div class="feed">
    { if (state.newPostCount > 0) {
        <button class="feed__new-posts-banner" onClick={handleLoadNew}>
            { state.newPostCount } new { if (state.newPostCount == 1) "post" else "posts" } — click to load
        </button>
    } }

    { when {
        state.loading && state.posts.isEmpty() -> <FeedSkeleton />
        state.error != null -> (
            <div class="feed__error" role="alert">
                <p>Failed to load posts: { state.error }</p>
                <button onClick={handleLoadMore}>Retry</button>
            </div>
        )
        state.posts.isEmpty() -> <EmptyFeed userId={props.userId} />
        else -> (
            <>
                <ul class="feed__list">
                    {for post in state.posts}
                        <li key={post.id}>
                            <PostCard post={post} />
                        </li>
                    {/for}
                </ul>
                <button
                    class="feed__load-more"
                    onClick={handleLoadMore}
                    disabled={state.loading}
                >
                    { if (state.loading) "Loading..." else "Load more" }
                </button>
            </>
        )
    } }
</div>
```

---

## 11.5 — Event Handling

aKt's event model is a round-trip protocol: a user interaction on the client generates a WebSocket message, the server's component process receives it and runs the corresponding handler, the handler returns a new state, the server diffs the new render against the previous render, and the diff is sent to the client to update the DOM.

The round trip typically completes in under 50ms on a co-located server. For latency-sensitive interactions, optimistic updates and JS hooks provide client-side immediacy.

### Standard Events

All standard DOM events are supported. Each maps to a server-side `handle_event` dispatch:

| aKt attribute | DOM event | Handler payload type |
|---|---|---|
| `onClick` | `click` | `ClickEvent` |
| `onChange` | `change` (input, select, textarea) | `ChangeEvent` |
| `onInput` | `input` | `InputEvent` |
| `onSubmit` | `submit` (form) | `SubmitEvent` |
| `onKeyDown` | `keydown` | `KeyboardEvent` |
| `onKeyUp` | `keyup` | `KeyboardEvent` |
| `onKeyPress` | `keypress` (deprecated, included for compatibility) | `KeyboardEvent` |
| `onFocus` | `focus` | `FocusEvent` |
| `onBlur` | `blur` | `FocusEvent` |
| `onMouseEnter` | `mouseenter` | `MouseEvent` |
| `onMouseLeave` | `mouseleave` | `MouseEvent` |
| `onMouseMove` | `mousemove` | `MouseEvent` |
| `onMouseDown` | `mousedown` | `MouseEvent` |
| `onMouseUp` | `mouseup` | `MouseEvent` |
| `onDragStart` | `dragstart` | `DragEvent` |
| `onDrop` | `drop` | `DragEvent` |
| `onScroll` | `scroll` | `ScrollEvent` |

**Full round-trip example for `onClick`:**

```kotlin
fun handleAddItem(state: CartState): Pair<CartState, List<Command>> =
    Pair(
        state.copy(items = state.items + CartItem.empty()),
        listOf(Command.run { Analytics.track(.addToCart) })
    )

---

<button
    onClick={handleAddItem}
    disabled={state.items.size >= 10}
    aria-label="Add item to cart"
>
    Add Item
</button>
```

What happens when the user clicks:
1. The aKt JS runtime detects the `click` event on the element
2. The runtime reads the element's encoded event binding (`data-akt-event-click="handleAddItem"`)
3. The runtime sends `{"type": "event", "name": "handleAddItem", "payload": {}}` over the WebSocket
4. The component's GenServer process receives the message, dispatches to `handleAddItem`
5. `handleAddItem` returns `(newState, [Command.run(…)])`
6. The GenServer updates its state, executes the command, runs `render(newState)`, diffs against the previous render
7. The diff `{"0": {"disabled": false}}` (for example) is sent to the client
8. The aKt JS runtime applies the patch

### Event Payload Types

```kotlin
data class ClickEvent(
    val target: ElementRef,
    val clientX: Int,
    val clientY: Int,
    val button: Int,        // 0 = left, 1 = middle, 2 = right
    val ctrlKey: Boolean,
    val shiftKey: Boolean,
    val altKey: Boolean,
    val metaKey: Boolean
)

data class InputEvent(
    val value: String,       // Current value of the input
    val target: ElementRef
)

data class ChangeEvent(
    val value: String,       // For text/select
    val checked: Boolean?,   // For checkboxes
    val files: List<FileRef>?, // For file inputs
    val target: ElementRef
)

data class KeyboardEvent(
    val key: String,         // "Enter", "Escape", "ArrowUp", etc.
    val code: String,        // "KeyA", "Enter", etc.
    val ctrlKey: Boolean,
    val shiftKey: Boolean,
    val altKey: Boolean,
    val metaKey: Boolean,
    val repeat: Boolean
)

data class SubmitEvent(
    val formData: Map<String, String>, // Form field name → value
    val target: ElementRef
)

data class FocusEvent(
    val target: ElementRef,
    val relatedTarget: ElementRef?
)

data class MouseEvent(
    val clientX: Int,
    val clientY: Int,
    val target: ElementRef
)

data class ScrollEvent(
    val scrollTop: Int,
    val scrollLeft: Int,
    val target: ElementRef
)
```

### Preventing Default Behavior

Use the `prevent:` modifier:

```kotlin
---

// Prevent form submission
<form onSubmit={handleSubmit} prevent:submit>
    ...
</form>

// Prevent link navigation
<a href="/dashboard" onClick={handleNavClick} prevent:click>
    Dashboard
</a>
```

The `prevent:` modifier is compiled to a client-side instruction: before sending the event to the server, call `event.preventDefault()`. This is necessary because the default browser behavior (form submission, link navigation) would navigate away from the page before the server can respond.

You can also return a command from an event handler that tells the client to navigate:

```kotlin
fun handleSubmit(event: SubmitEvent, state: FormState): Pair<FormState, List<Command>> {
    val errors = validate(event.formData)
    return if (errors.isEmpty()) {
        Pair(state, listOf(Command.navigate("/dashboard")))
    } else {
        Pair(state.copy(errors = errors), emptyList())
    }
}
```

### Debouncing and Throttling

The `debounce:` and `throttle:` modifiers delay or throttle event sending:

```kotlin
---

// Debounce: wait 300ms after last keystroke before sending
<input
    type="search"
    value={state.query}
    onInput={handleSearch}
    debounce:input={300}
/>

// Throttle: send at most once per 200ms
<div
    onMouseMove={handleMouseMove}
    throttle:mousemove={200}
/>
```

`debounce:` is implemented client-side by the aKt JS runtime: the runtime holds the event and only sends it after the specified delay with no new events of the same type on the same element. `throttle:` sends the event immediately and then suppresses subsequent events of the same type for the specified duration.

### JS Hooks for Client-Side Behavior

For behavior that genuinely cannot be implemented server-side — animation, canvas, third-party JavaScript libraries, clipboard API, browser geolocation — the `use:` directive binds a JS hook to a DOM element:

```kotlin
---

<canvas
    use:Chart
    data-config={Json.encode(chartConfig)}
    width="800"
    height="400"
/>
```

JS hooks are registered in the aKt JS runtime configuration. The hook lifecycle:

```javascript
// In your app's JS bundle (e.g., app.js)
import { AktRuntime } from "akt-runtime"

AktRuntime.start({
    hooks: {
        Chart: {
            // Called when the element is first added to the DOM
            mounted() {
                const config = JSON.parse(this.el.dataset.config)
                this.chart = new Chart(this.el, config)
            },

            // Called after the server sends a patch that affects this element
            updated() {
                const config = JSON.parse(this.el.dataset.config)
                this.chart.data = config.data
                this.chart.update()
            },

            // Called when the element is removed from the DOM
            destroyed() {
                this.chart.destroy()
            },

            // Called when the server sends a custom event to this hook
            handleEvent(event) {
                if (event.type === "highlight") {
                    this.chart.highlight(event.dataIndex)
                }
            }
        }
    }
})
```

The `this` context inside a JS hook provides:

- `this.el` — the DOM element
- `this.pushEvent(name, payload)` — sends an event to the server component
- `this.handleEvent(name, callback)` — registers a listener for server-sent events

Sending events from hook to server:

```javascript
// In JS hook
this.pushEvent("chart_point_clicked", { dataIndex: point.index, value: point.value })
```

```kotlin
// In component — receiving the hook event
fun handle_info(msg: HookEvent<"chart_point_clicked">, state: DashboardState): DashboardState =
    state.copy(selectedDataIndex = msg.payload["dataIndex"] as Int)
```

Sending events from server to hook:

```kotlin
fun handleHighlightPoint(index: Int, state: DashboardState): Pair<DashboardState, List<Command>> =
    Pair(
        state.copy(highlightedIndex = index),
        listOf(Command.sendToHook("Chart", "highlight", mapOf("dataIndex" to index)))
    )
```

### Optimistic Updates

For low-latency feedback on user interactions, optimistic updates allow the UI to reflect the expected outcome of an event before the server confirms it:

```kotlin
data class LikeButtonState(
    val liked: Boolean,
    val likeCount: Int,
    val pending: Boolean = false
)

fun handleLike(state: LikeButtonState, props: LikeButtonProps): Pair<LikeButtonState, List<Command>> {
    // Optimistic update: immediately reflect the change
    val optimisticState = state.copy(
        liked = !state.liked,
        likeCount = if (state.liked) state.likeCount - 1 else state.likeCount + 1,
        pending = true
    )
    return Pair(
        optimisticState,
        listOf(Command.async("toggle_like") { LikeService.toggle(props.postId) })
    )
}

fun handle_info(msg: AsyncResult<"toggle_like", LikeResult>, state: LikeButtonState): LikeButtonState =
    when (msg) {
        is Ok -> state.copy(
            liked = msg.value.liked,
            likeCount = msg.value.count,
            pending = false
        )
        is Err -> state.copy(
            // Revert on error
            liked = !state.liked,
            likeCount = if (state.liked) state.likeCount + 1 else state.likeCount - 1,
            pending = false
        )
    }
```

### Complete Form Example

```kotlin
// ContactForm.akt

import kore.akt.*
import kore.akt.live.*
import myapp.services.MailService
import myapp.domain.validation.*

@LiveComponent
props ContactFormProps {
    val onSuccess: (() -> Unit)? = null
}

data class FormValues(
    val name: String = "",
    val email: String = "",
    val subject: String = "",
    val message: String = ""
)

data class ContactFormState(
    val values: FormValues = FormValues(),
    val errors: Map<String, String> = emptyMap(),
    val submitting: Boolean = false,
    val submitted: Boolean = false,
    val serverError: String? = null
)

fun mount(props: ContactFormProps): ContactFormState = ContactFormState()

fun handleFieldChange(event: InputEvent, state: ContactFormState): ContactFormState {
    val fieldName = event.target.name
    val newValues = when (fieldName) {
        "name"    -> state.values.copy(name = event.value)
        "email"   -> state.values.copy(email = event.value)
        "subject" -> state.values.copy(subject = event.value)
        "message" -> state.values.copy(message = event.value)
        else      -> state.values
    }
    // Clear field error on change
    return state.copy(
        values = newValues,
        errors = state.errors - fieldName
    )
}

fun handleBlur(event: FocusEvent, state: ContactFormState): ContactFormState {
    val fieldName = event.target.name
    val error = validateField(fieldName, state.values)
    return if (error != null) {
        state.copy(errors = state.errors + (fieldName to error))
    } else {
        state.copy(errors = state.errors - fieldName)
    }
}

fun handleSubmit(event: SubmitEvent, state: ContactFormState, props: ContactFormProps): Pair<ContactFormState, List<Command>> {
    val allErrors = validateAll(state.values)
    return if (allErrors.isNotEmpty()) {
        Pair(state.copy(errors = allErrors), emptyList())
    } else {
        Pair(
            state.copy(submitting = true, serverError = null),
            listOf(Command.async("send_message") { MailService.send(state.values) })
        )
    }
}

fun handle_info(msg: AsyncResult<"send_message", Unit>, state: ContactFormState, props: ContactFormProps): Pair<ContactFormState, List<Command>> =
    when (msg) {
        is Ok -> {
            val commands = if (props.onSuccess != null) {
                listOf(Command.run { props.onSuccess!!() })
            } else emptyList()
            Pair(state.copy(submitted = true, submitting = false), commands)
        }
        is Err -> Pair(state.copy(submitting = false, serverError = "Failed to send message. Please try again."), emptyList())
    }

// Validation helpers (in logic section, not rendered)
fun validateField(field: String, values: FormValues): String? = when (field) {
    "name"    -> if (values.name.isBlank()) "Name is required" else null
    "email"   -> if (!values.email.matches(Regex.email)) "Valid email required" else null
    "subject" -> if (values.subject.isBlank()) "Subject is required" else null
    "message" -> if (values.message.length < 10) "Message must be at least 10 characters" else null
    else      -> null
}

fun validateAll(values: FormValues): Map<String, String> =
    listOf("name", "email", "subject", "message")
        .mapNotNull { field -> validateField(field, values)?.let { field to it } }
        .toMap()

---

{ if (state.submitted) {
    <div class="contact-form__success" role="status">
        <h3>Message sent!</h3>
        <p>We'll get back to you within 24 hours.</p>
    </div>
} else {
    <form
        class="contact-form"
        onSubmit={handleSubmit}
        prevent:submit
        novalidate
        aria-label="Contact form"
    >
        { if (state.serverError != null) {
            <div class="contact-form__server-error" role="alert">
                { state.serverError }
            </div>
        } }

        <div class={"form-field" + if (state.errors["name"] != null) " form-field--error" else ""}>
            <label for="name">Name *</label>
            <input
                id="name"
                name="name"
                type="text"
                value={state.values.name}
                onInput={handleFieldChange}
                onBlur={handleBlur}
                aria-required="true"
                aria-invalid={state.errors["name"] != null}
                aria-describedby={ if (state.errors["name"] != null) "name-error" else null }
                autocomplete="name"
            />
            { if (state.errors["name"] != null) {
                <p id="name-error" class="form-field__error" role="alert">
                    { state.errors["name"] }
                </p>
            } }
        </div>

        <div class={"form-field" + if (state.errors["email"] != null) " form-field--error" else ""}>
            <label for="email">Email *</label>
            <input
                id="email"
                name="email"
                type="email"
                value={state.values.email}
                onInput={handleFieldChange}
                onBlur={handleBlur}
                aria-required="true"
                aria-invalid={state.errors["email"] != null}
                aria-describedby={ if (state.errors["email"] != null) "email-error" else null }
                autocomplete="email"
            />
            { if (state.errors["email"] != null) {
                <p id="email-error" class="form-field__error" role="alert">
                    { state.errors["email"] }
                </p>
            } }
        </div>

        <div class={"form-field" + if (state.errors["subject"] != null) " form-field--error" else ""}>
            <label for="subject">Subject *</label>
            <input
                id="subject"
                name="subject"
                type="text"
                value={state.values.subject}
                onInput={handleFieldChange}
                onBlur={handleBlur}
                aria-required="true"
                aria-invalid={state.errors["subject"] != null}
            />
            { if (state.errors["subject"] != null) {
                <p class="form-field__error" role="alert">{ state.errors["subject"] }</p>
            } }
        </div>

        <div class={"form-field" + if (state.errors["message"] != null) " form-field--error" else ""}>
            <label for="message">Message *</label>
            <textarea
                id="message"
                name="message"
                rows={6}
                value={state.values.message}
                onInput={handleFieldChange}
                onBlur={handleBlur}
                aria-required="true"
                aria-invalid={state.errors["message"] != null}
            />
            { if (state.errors["message"] != null) {
                <p class="form-field__error" role="alert">{ state.errors["message"] }</p>
            } }
        </div>

        <button
            type="submit"
            class="btn btn--primary"
            disabled={state.submitting}
            aria-busy={state.submitting}
        >
            { if (state.submitting) "Sending..." else "Send Message" }
        </button>
    </form>
} }
```

---

## 11.6 — Server vs Client Components

### The Default: Everything is a Server Component

In aKt, the default execution model for every `.akt` component is server-side. The component runs as a GenServer process on the BEAM. No JavaScript is shipped to the browser for the component's logic. The server renders HTML, maintains state, processes events via WebSocket, and sends diffs.

This is a stronger default than Next.js server components, which require explicit opt-in (`export async function Page()`). In aKt, you do not opt into being a server component. You opt out.

The practical implications:
- Zero JavaScript bundle growth as you add components
- Full access to server resources (database, file system, process registry, PubSub) directly in components without an API layer
- No serialization boundary between component logic and data layer — you call your services directly
- Server-side secrets are never exposed to the client
- Search engine crawlers see fully-rendered HTML

### `use client` — Client-Side Islands

When a component genuinely needs to run on the client — because it wraps a third-party JavaScript library, requires browser APIs unavailable server-side, or needs sub-millisecond interaction latency that a round-trip cannot provide — it is declared with `use client`:

```kotlin
// SortableList.akt
use client  // Must be the first non-comment line

import akt.client.*

props SortableListProps {
    val items: List<SortableItem>
    val onReorder: (List<String>) -> Unit  // Callback to parent server component
}

data class SortableListState(
    val items: List<SortableItem>
)

fun mount(props: SortableListProps): SortableListState =
    SortableListState(items = props.items)

---

<ul
    use:Sortable
    data-items={Json.encode(state.items.map { it.id })}
    class="sortable-list"
>
    {for item in state.items}
        <li key={item.id} class="sortable-list__item" data-id={item.id}>
            { item.label }
        </li>
    {/for}
</ul>
```

A `use client` component:
- Is compiled to JavaScript (TypeScript via the aKt-to-TS compiler backend) and included in the browser bundle
- Runs in the browser, not on the server
- Does not have a corresponding GenServer process
- Has its own local state managed in the browser
- Communicates with its parent server component via props and callbacks

The `use:Sortable` hook in the example above connects to a JavaScript drag-and-drop library:

```javascript
// In app.js
AktRuntime.start({
    hooks: {
        Sortable: {
            mounted() {
                this.sortable = new SortableJS(this.el, {
                    onEnd: (event) => {
                        const ids = Array.from(this.el.children).map(el => el.dataset.id)
                        this.pushEvent("reordered", { ids })
                    }
                })
            },
            destroyed() { this.sortable.destroy() }
        }
    }
})
```

### The Boundary Rules

**Rule 1: Server components can use client components.** A server component's template may include `<SortableList>` even though `SortableList` is a client component. The server renders the island's initial HTML (from the `mount` state), marks it with the island metadata, and the client-side runtime hydrates it.

```kotlin
// Dashboard.akt (server component — no 'use client')

---

<div class="dashboard">
    <DashboardStats stats={state.stats} />       // Server component
    <RecentActivity feed={state.feed} />          // Server component
    <SortableList                                  // Client component (island)
        items={state.widgets}
        onReorder={handleWidgetReorder}
    />
</div>
```

**Rule 2: Client components cannot use server components.** A `use client` component's template cannot include server components. If it attempts to, the compiler emits an error: `Server component 'DashboardStats' cannot be used inside client component 'SortableList'. Move 'DashboardStats' to the server component tree or convert it to a client component.`

**Rule 3: Props crossing the boundary must be serializable.** The parent server component passes props to the client island via the initial HTML payload. Props must be JSON-serializable: primitives, strings, lists, and maps of primitives. The following types cannot cross the boundary:
- Function references (except callbacks, which are encoded as event names)
- GenServer PIDs
- Opaque Erlang terms
- Types annotated `@NotSerializable`

The compiler verifies this at the call site. If `state.connection` (type `DBConnection`) is passed as a prop to a client component, the compiler emits: `Type 'DBConnection' is not serializable and cannot cross the server/client boundary`.

Callbacks (functions passed as props to client components) are serialized as opaque event identifiers. When the client component invokes the callback, it sends an event to the server, which dispatches the callback on the server side.

**Rule 4: Serializable types include:** `Int`, `Long`, `Float`, `Double`, `Boolean`, `String`, `List<T>` where T is serializable, `Map<String, T>` where T is serializable, `data class` types where all fields are serializable, and types implementing `AktSerializable`.

### Streaming and Suspense

aKt supports streaming initial HTML: the server begins sending the page's HTML immediately, with placeholder content for components whose data has not yet loaded, then streams the updates as data arrives.

The `suspend` modifier on a component's `loadData` function marks it as async-loading:

```kotlin
// UserProfile.akt

@LiveComponent
props UserProfileProps {
    val userId: String
}

data class UserProfileState(
    val user: User? = null,
    val posts: List<Post> = emptyList(),
    val loading: Boolean = true
)

// loadData runs before mount — used for initial SSR data
// The page HTML is streamed with a placeholder until this resolves
suspend fun loadData(props: UserProfileProps): UserProfileState {
    val user = UserService.getById(props.userId)
    return UserProfileState(user = user, loading = false)
}

fun mount(props: UserProfileProps, initialState: UserProfileState): Pair<UserProfileState, List<Command>> =
    Pair(
        initialState,
        listOf(Command.async("load_posts") { PostService.getByUser(props.userId) })
    )

fun handle_info(msg: AsyncResult<"load_posts", List<Post>>, state: UserProfileState): UserProfileState =
    state.copy(posts = msg.value)
```

While `loadData` is running, the page renders the corresponding `_loading.akt` template (see Section 11.7). Once `loadData` resolves, the full component renders. This is the server-side equivalent of React Suspense's streaming SSR.

**Per-component async loading with `assign_async`:**

For data that loads after mount (not blocking initial render), use `Command.async`:

```kotlin
data class ProductPageState(
    val product: Product,
    val relatedProducts: AsyncValue<List<Product>> = AsyncValue.loading(),
    val reviews: AsyncValue<List<Review>> = AsyncValue.loading()
)

fun mount(props: ProductPageProps): Pair<ProductPageState, List<Command>> =
    Pair(
        ProductPageState(product = props.product),
        listOf(
            Command.async("related") { ProductService.getRelated(props.product.id, limit = 4) },
            Command.async("reviews") { ReviewService.getForProduct(props.product.id, limit = 10) }
        )
    )

fun handle_info(msg: AsyncResult<"related", List<Product>>, state: ProductPageState): ProductPageState =
    state.copy(relatedProducts = when (msg) {
        is Ok  -> AsyncValue.ready(msg.value)
        is Err -> AsyncValue.error(msg.reason.toString())
    })

fun handle_info(msg: AsyncResult<"reviews", List<Review>>, state: ProductPageState): ProductPageState =
    state.copy(reviews = when (msg) {
        is Ok  -> AsyncValue.ready(msg.value)
        is Err -> AsyncValue.error(msg.reason.toString())
    })
```

```kotlin
---

<div class="product-page">
    <ProductHero product={state.product} />

    <section class="product-page__related">
        <h2>Related Products</h2>
        { when (state.relatedProducts) {
            is AsyncValue.Loading -> <ProductGridSkeleton count={4} />
            is AsyncValue.Error   -> <p class="error">{ state.relatedProducts.message }</p>
            is AsyncValue.Ready   -> <ProductGrid products={state.relatedProducts.value} />
        } }
    </section>

    <section class="product-page__reviews">
        <h2>Reviews</h2>
        { when (state.reviews) {
            is AsyncValue.Loading -> <ReviewListSkeleton count={3} />
            is AsyncValue.Error   -> <p class="error">Could not load reviews</p>
            is AsyncValue.Ready   -> <ReviewList reviews={state.reviews.value} />
        } }
    </section>
</div>
```

**`AsyncValue<T>` is a sealed class provided by the aKt standard library:**

```kotlin
sealed class AsyncValue<out T> {
    object Loading : AsyncValue<Nothing>()
    data class Error(val message: String) : AsyncValue<Nothing>()
    data class Ready<T>(val value: T) : AsyncValue<T>()

    companion object {
        fun loading(): AsyncValue<Nothing> = Loading
        fun <T> ready(value: T): AsyncValue<T> = Ready(value)
        fun error(message: String): AsyncValue<Nothing> = Error(message)
    }
}
```

---

## 11.7 — File-Based Routing

### Directory Structure

aKt follows Next.js's App Router conventions adapted for the BEAM. Routes are declared by file position in the `pages/` directory:

```
pages/
  index.akt                   → GET /
  about.akt                   → GET /about
  users/
    index.akt                 → GET /users
    new.akt                   → GET /users/new
    [id].akt                  → GET /users/:id
    [id]/
      edit.akt                → GET /users/:id/edit
      posts.akt               → GET /users/:id/posts
      posts/
        [postId].akt          → GET /users/:id/posts/:postId
  blog/
    [...slug].akt             → GET /blog/* (wildcard, captures all segments)
  api/                        → (API routes — handled by Ping directly, not aKt)
    users.akt                 → REST endpoint, not a LiveComponent
```

Dynamic segments are declared with `[paramName]`. The parameter is available in the component as `params.id`, `params.postId`, etc. The type of all route parameters is `String`; parsing to other types is done explicitly:

```kotlin
// pages/users/[id].akt

props UserPageProps {
    val id: String  // Automatically populated from route
}

// OR with explicit parsing:
props UserPageProps {
    val id: String
}

suspend fun loadData(props: UserPageProps): UserPageState {
    val userId = props.id.toLongOrNull()
        ?: throw NotFoundException("Invalid user id: ${props.id}")
    val user = UserService.getById(userId)
        ?: throw NotFoundException("User not found: $userId")
    return UserPageState(user = user)
}
```

Wildcard routes `[...slug]` capture all remaining path segments as a `List<String>`:

```kotlin
// pages/blog/[...slug].akt

props BlogPageProps {
    val slug: List<String>  // e.g., ["2024", "06", "my-post-title"]
}
```

### Layouts

`_layout.akt` wraps all routes in its directory. Layouts are composable: a layout in a subdirectory wraps its routes and is itself wrapped by the parent directory's layout.

```
pages/
  _layout.akt        → Root layout (wraps everything)
  index.akt
  users/
    _layout.akt      → Users layout (wraps all /users/* routes)
    index.akt
    [id].akt
```

```kotlin
// pages/_layout.akt — Root layout

import myapp.components.*

props RootLayoutProps {
    val session: Session
}

data class RootLayoutState(
    val notifications: List<Notification> = emptyList()
)

fun mount(props: RootLayoutProps): Pair<RootLayoutState, List<Command>> =
    Pair(
        RootLayoutState(),
        listOf(
            Command.async("load_notifications") {
                NotificationService.getUnread(props.session.userId)
            },
            Command.subscribe("notifications:${props.session.userId}")
        )
    )

fun handle_info(msg: AsyncResult<"load_notifications", List<Notification>>, state: RootLayoutState): RootLayoutState =
    state.copy(notifications = msg.value)

fun handle_info(msg: NewNotification, state: RootLayoutState): RootLayoutState =
    state.copy(notifications = listOf(msg.notification) + state.notifications)

---

<div class="app">
    <header class="app__header">
        <SiteNav session={props.session} />
        <NotificationBell count={state.notifications.size} />
    </header>
    <main class="app__main">
        { children }
    </main>
    <footer class="app__footer">
        <SiteFooter />
    </footer>
</div>
```

```kotlin
// pages/users/_layout.akt — Users section layout

props UsersLayoutProps {
    val session: Session
}

---

<div class="users-section">
    <aside class="users-section__sidebar">
        <UsersSidebar />
    </aside>
    <div class="users-section__content">
        { children }
    </div>
</div>
```

The root layout receives the full `children` of the page. Nested layouts receive the page content as their children and are themselves the `children` of the root layout. The composition is:

```
RootLayout
  └── UsersLayout (children of RootLayout)
        └── UserPage (children of UsersLayout)
```

### Loading and Error States

`_loading.akt` is rendered while the page's `loadData` is executing. It receives the route params but not the loaded data:

```kotlin
// pages/users/[id]/_loading.akt

props UserPageLoadingProps {
    val id: String
}

---

<div class="user-page-skeleton">
    <div class="skeleton skeleton--avatar" aria-hidden="true" />
    <div class="skeleton skeleton--title" aria-hidden="true" />
    <div class="skeleton skeleton--text" aria-hidden="true" />
    <div class="skeleton skeleton--text" aria-hidden="true" />
    <p class="sr-only" role="status">Loading user profile...</p>
</div>
```

`_error.akt` is rendered when the page's `loadData` throws an exception or when the component's GenServer crashes and restarts:

```kotlin
// pages/users/[id]/_error.akt

props UserPageErrorProps {
    val error: AktError    // The caught exception
    val id: String         // Route params still available
}

---

<div class="error-state" role="alert">
    { when (props.error) {
        is NotFoundException -> (
            <div>
                <h2>User Not Found</h2>
                <p>No user exists with ID { props.id }.</p>
                <a href="/users">Back to Users</a>
            </div>
        )
        is AuthorizationException -> (
            <div>
                <h2>Access Denied</h2>
                <p>You do not have permission to view this profile.</p>
            </div>
        )
        else -> (
            <div>
                <h2>Something went wrong</h2>
                <p>An unexpected error occurred. Please try again.</p>
                <button onClick={handleRetry}>Retry</button>
            </div>
        )
    } }
</div>
```

### Integration with Ping

The Ping router DSL is generated automatically from the `pages/` directory structure. The developer does not write router entries for aKt pages — the compiler emits them:

**Generated Ping router (illustrative; not written by hand):**

```kotlin
// Generated by aKt compiler — do not edit manually
// .build/generated/router.kore

router {
    pipeline("live") {
        plug(AktRuntime.LiveSocket)
        plug(AktRuntime.SessionMiddleware)
    }

    scope("/", pipeline = "live") {
        live("/",            'KorE.Pages.Index')
        live("/about",       'KorE.Pages.About')

        live("/users",       'KorE.Pages.Users.Index')
        live("/users/new",   'KorE.Pages.Users.New')
        live("/users/:id",   'KorE.Pages.Users.Id',      params = ["id"])
        live("/users/:id/edit", 'KorE.Pages.Users.Id.Edit', params = ["id"])

        live("/blog/*slug",  'KorE.Pages.Blog.Slug',     params = ["slug"])
    }
}
```

The `live/3` function is a Ping extension for aKt routes. It registers both the initial HTTP GET handler (which renders the static HTML shell and initiates the WebSocket connection) and the WebSocket event handler for the component.

### Programmatic Navigation

Navigation inside aKt components uses `Command.navigate` and `Command.patch`:

```kotlin
// Full navigation: unmounts current component, mounts new one
// Equivalent to LiveView's push_navigate
fun handleViewUser(userId: String, state: UserListState): Pair<UserListState, List<Command>> =
    Pair(state, listOf(Command.navigate("/users/$userId")))

// Patch: updates URL and props without unmounting the component
// Equivalent to LiveView's push_patch
// Use when you're navigating within the same component (pagination, filters, etc.)
fun handlePageChange(page: Int, state: UserListState): Pair<UserListState, List<Command>> =
    Pair(state.copy(loading = true), listOf(Command.patch("/users?page=$page")))

// Patch triggers 'update' on the component with new params
fun update(newProps: UserListProps, oldProps: UserListProps, state: UserListState): Pair<UserListState, List<Command>> =
    if (newProps.page != oldProps.page) {
        Pair(
            state.copy(loading = true),
            listOf(Command.async("load_users") { UserService.getPage(newProps.page) })
        )
    } else {
        Pair(state, emptyList())
    }
```

Navigation targets are validated at compile time when string literals are used. `Command.navigate("/users")` will produce a compile warning if `/users` does not match any page in the `pages/` directory. Dynamic paths constructed at runtime are not validated at compile time.

### Page-Level Data Loading

The `loadData` function is the aKt equivalent of Next.js's `getServerSideProps`. It runs on the server before the component is mounted, and its result becomes the initial state:

```kotlin
// pages/products/[id].akt

props ProductPageProps {
    val id: String
}

data class ProductPageState(
    val product: Product,
    val relatedProducts: List<Product>,
    val inStock: Boolean,
    val reviews: AsyncValue<List<Review>> = AsyncValue.loading()
)

// Runs before mount — blocks initial HTML until resolved
// Throws NotFoundException → shows _error.akt
// Throws AuthorizationException → redirects to login
suspend fun loadData(props: ProductPageProps, session: Session): ProductPageState {
    val id = props.id.toLongOrNull() ?: throw NotFoundException()
    val (product, related, stock) = awaitAll(
        async { ProductService.getById(id) ?: throw NotFoundException() },
        async { ProductService.getRelated(id, limit = 4) },
        async { InventoryService.checkStock(id) }
    )
    return ProductPageState(product = product, relatedProducts = related, inStock = stock)
}

fun mount(props: ProductPageProps, initialState: ProductPageState): Pair<ProductPageState, List<Command>> =
    Pair(
        initialState,
        listOf(Command.async("load_reviews") { ReviewService.getForProduct(props.id.toLong()!!, limit = 10) })
    )
```

`loadData` receives the route props (including all path params and query params) and the current session. It may be `suspend` (blocking async) or regular (synchronous). Throwing a `NotFoundException` renders `_error.akt`. Returning `Command.redirect(...)` is done via a special redirect exception: `throw RedirectException("/login")`.

Query parameters are exposed as props when declared:

```kotlin
// pages/users/index.akt

props UsersIndexProps {
    val page: Int = 1      // ?page=2 → props.page = 2
    val search: String = ""  // ?search=alice → props.search = "alice"
    val sort: SortOrder = .nameAsc
}
```

The compiler generates the query param parsing from the props declaration. String types accept the raw value; typed props use the type's `fromString` conversion. If the query param cannot be parsed to the declared type, the default value is used.

---

## 11.8 — Async Data Loading

### `assign_async` Equivalent: `Command.async`

Phoenix LiveView's `assign_async` runs a function asynchronously and updates the socket assigns when it completes. aKt's equivalent is `Command.async`:

```kotlin
// LiveView (Elixir)
assign_async(socket, [:user, :posts], fn ->
    {:ok, %{
        user: Accounts.get_user!(user_id),
        posts: Posts.list_posts(user_id)
    }}
end)

// aKt equivalent
Command.async("load_user_data") {
    val user = UserService.getById(userId)
    val posts = PostService.getByUser(userId)
    UserData(user = user, posts = posts)
}
```

`Command.async(name, block)` creates an asynchronous command. The block runs in a separate coroutine on the BEAM. When it completes, it sends an `AsyncResult<name, T>` message to the component process, which is handled by `handle_info`.

**Naming matters**: The name string is used as a type-level tag for the result. The compiler verifies that every `Command.async("name")` call has a corresponding `handle_info(msg: AsyncResult<"name", T>)` handler. An `Command.async` without a corresponding handler is a compile warning.

**Cancellation**: If the component is unmounted or a new `Command.async("name")` is issued before the previous one completes, the previous one's result is discarded (not sent to the component). This prevents stale data races.

```kotlin
// Full async loading example
data class UserDashboardState(
    val user: AsyncValue<User> = AsyncValue.loading(),
    val stats: AsyncValue<UserStats> = AsyncValue.loading(),
    val recentActivity: AsyncValue<List<Activity>> = AsyncValue.loading()
)

fun mount(props: UserDashboardProps): Pair<UserDashboardState, List<Command>> =
    Pair(
        UserDashboardState(),
        listOf(
            Command.async("load_user") { UserService.getById(props.userId) },
            Command.async("load_stats") { StatsService.getForUser(props.userId) },
            Command.async("load_activity") { ActivityService.getRecent(props.userId, limit = 10) }
        )
    )

fun handle_info(msg: AsyncResult<"load_user", User>, state: UserDashboardState): UserDashboardState =
    state.copy(user = when (msg) {
        is Ok  -> AsyncValue.ready(msg.value)
        is Err -> AsyncValue.error(msg.reason.toString())
    })

fun handle_info(msg: AsyncResult<"load_stats", UserStats>, state: UserDashboardState): UserDashboardState =
    state.copy(stats = when (msg) {
        is Ok  -> AsyncValue.ready(msg.value)
        is Err -> AsyncValue.error(msg.reason.toString())
    })

fun handle_info(msg: AsyncResult<"load_activity", List<Activity>>, state: UserDashboardState): UserDashboardState =
    state.copy(recentActivity = when (msg) {
        is Ok  -> AsyncValue.ready(msg.value)
        is Err -> AsyncValue.error(msg.reason.toString())
    })
```

### Loading States

The `AsyncValue<T>` sealed class (defined in Section 11.6) provides the three states. The template `when` expression handles them:

```kotlin
---

<div class="user-dashboard">
    { when (state.user) {
        is AsyncValue.Loading -> <div class="skeleton skeleton--profile" aria-label="Loading profile..." />
        is AsyncValue.Error   -> <ErrorCard message={state.user.message} onRetry={handleRetryUser} />
        is AsyncValue.Ready   -> <UserProfileCard user={state.user.value} />
    } }

    <div class="dashboard-stats">
        { when (state.stats) {
            is AsyncValue.Loading -> <StatsSkeleton />
            is AsyncValue.Error   -> <p class="error">Stats unavailable</p>
            is AsyncValue.Ready   -> <StatsGrid stats={state.stats.value} />
        } }
    </div>

    <section class="recent-activity">
        <h2>Recent Activity</h2>
        { when (state.recentActivity) {
            is AsyncValue.Loading -> <ActivityListSkeleton />
            is AsyncValue.Error   -> <p class="error">Activity unavailable</p>
            is AsyncValue.Ready when state.recentActivity.value.isEmpty() -> (
                <p class="empty">No recent activity</p>
            )
            is AsyncValue.Ready   -> (
                <ul class="activity-list">
                    {for activity in state.recentActivity.value}
                        <li key={activity.id}><ActivityItem activity={activity} /></li>
                    {/for}
                </ul>
            )
        } }
    </section>
</div>
```

### Stale Data While Reloading

To show stale data while refreshing (e.g., for a pull-to-refresh or auto-refresh pattern), extend `AsyncValue` with a `Refreshing` state:

```kotlin
sealed class AsyncValue<out T> {
    object Loading : AsyncValue<Nothing>()
    data class Error(val message: String) : AsyncValue<Nothing>()
    data class Ready<T>(val value: T) : AsyncValue<T>()
    data class Refreshing<T>(val staleValue: T) : AsyncValue<T>()

    val isLoading: Boolean get() = this is Loading || this is Refreshing
    val valueOrNull: T? get() = when (this) {
        is Ready -> value
        is Refreshing -> staleValue
        else -> null
    }
}

fun handleRefresh(state: FeedState, props: FeedProps): Pair<FeedState, List<Command>> =
    Pair(
        state.copy(
            posts = when (val p = state.posts) {
                is AsyncValue.Ready -> AsyncValue.Refreshing(p.value)
                else -> AsyncValue.Loading
            }
        ),
        listOf(Command.async("load_posts") { PostService.getRecent(props.userId) })
    )
```

```kotlin
---

<div class="feed">
    <div class="feed__header">
        <h2>Your Feed</h2>
        <button
            onClick={handleRefresh}
            disabled={state.posts.isLoading}
            aria-label="Refresh feed"
        >
            { if (state.posts.isLoading) "Refreshing..." else "Refresh" }
        </button>
    </div>

    { when (state.posts) {
        is AsyncValue.Loading    -> <FeedSkeleton />
        is AsyncValue.Refreshing -> (
            // Show stale data with a refreshing indicator
            <>
                <div class="feed__refreshing-banner" role="status" aria-live="polite">
                    Refreshing...
                </div>
                <PostList posts={state.posts.staleValue} />
            </>
        )
        is AsyncValue.Ready      -> <PostList posts={state.posts.value} />
        is AsyncValue.Error      -> <FeedError message={state.posts.message} onRetry={handleRefresh} />
    } }
</div>
```

### Parallel Data Loading

`Command.async` calls in a list execute in parallel automatically — each one spawns a separate coroutine. They resolve independently and trigger separate `handle_info` calls:

```kotlin
// These three run concurrently
fun mount(props: PageProps): Pair<PageState, List<Command>> =
    Pair(
        PageState(),
        listOf(
            Command.async("users")    { UserService.getAll() },
            Command.async("tags")     { TagService.getAll() },
            Command.async("settings") { SettingsService.get() }
        )
    )
```

For cases where you need all results before proceeding, accumulate them in state and render the final view only when all are ready:

```kotlin
data class PageState(
    val users: AsyncValue<List<User>> = AsyncValue.loading(),
    val tags: AsyncValue<List<Tag>> = AsyncValue.loading(),
    val settings: AsyncValue<Settings> = AsyncValue.loading()
)

// Computed property: true when all async values are ready
fun allLoaded(state: PageState): Boolean =
    state.users is AsyncValue.Ready &&
    state.tags is AsyncValue.Ready &&
    state.settings is AsyncValue.Ready

---

{ if (!allLoaded(state)) {
    <PageLoadingSkeleton />
} else {
    <PageContent
        users={(state.users as AsyncValue.Ready).value}
        tags={(state.tags as AsyncValue.Ready).value}
        settings={(state.settings as AsyncValue.Ready).value}
    />
} }
```

### Streaming

The aKt diff protocol inherently supports streaming: each `handle_info` call produces a new diff that is sent to the client immediately. There is no "flush" step. As each `Command.async` completes and the corresponding `handle_info` runs, the client receives an incremental update.

This means streaming is not a special feature — it is the default behavior when multiple async commands are in flight. The client shows each piece of data as it arrives, not waiting for all data to load.

### Complete Async Example: User Profile Page

```kotlin
// pages/users/[id].akt

import kore.akt.*
import kore.akt.live.*
import myapp.services.*
import myapp.domain.*

@LiveComponent
props UserProfileProps {
    val id: String
}

data class UserProfileState(
    val user: User,                                              // Loaded in loadData (required)
    val posts: AsyncValue<List<Post>> = AsyncValue.loading(),
    val followers: AsyncValue<List<User>> = AsyncValue.loading(),
    val notifications: AsyncValue<Int> = AsyncValue.loading(),
    val isFollowing: Boolean = false,
    val followPending: Boolean = false
)

// Blocks initial render — must resolve before page shows
suspend fun loadData(props: UserProfileProps, session: Session): UserProfileState {
    val userId = props.id.toLongOrNull() ?: throw NotFoundException()
    val user = UserService.getById(userId) ?: throw NotFoundException()
    return UserProfileState(
        user = user,
        isFollowing = FollowService.isFollowing(session.userId, userId)
    )
}

fun mount(props: UserProfileProps, initialState: UserProfileState): Pair<UserProfileState, List<Command>> =
    Pair(
        initialState,
        listOf(
            Command.async("load_posts") { PostService.getByUser(props.id, limit = 20) },
            Command.async("load_followers") { FollowService.getFollowers(props.id) },
            Command.async("load_notif_count") { NotificationService.getCount(props.id) },
            Command.subscribe("profile:${props.id}")
        )
    )

fun handle_info(msg: AsyncResult<"load_posts", List<Post>>, state: UserProfileState): UserProfileState =
    state.copy(posts = when (msg) {
        is Ok  -> AsyncValue.ready(msg.value)
        is Err -> AsyncValue.error("Could not load posts")
    })

fun handle_info(msg: AsyncResult<"load_followers", List<User>>, state: UserProfileState): UserProfileState =
    state.copy(followers = when (msg) {
        is Ok  -> AsyncValue.ready(msg.value)
        is Err -> AsyncValue.error("Could not load followers")
    })

fun handle_info(msg: AsyncResult<"load_notif_count", Int>, state: UserProfileState): UserProfileState =
    state.copy(notifications = when (msg) {
        is Ok  -> AsyncValue.ready(msg.value)
        is Err -> AsyncValue.error("unavailable")
    })

fun handle_info(msg: ProfileUpdated, state: UserProfileState): Pair<UserProfileState, List<Command>> =
    Pair(
        state.copy(user = msg.user),
        emptyList()
    )

fun handleFollow(state: UserProfileState, props: UserProfileProps): Pair<UserProfileState, List<Command>> =
    Pair(
        state.copy(
            isFollowing = !state.isFollowing,
            followPending = true,
            followers = when (val f = state.followers) {
                is AsyncValue.Ready -> if (state.isFollowing)
                    AsyncValue.ready(f.value.filter { it.id != props.id })
                else
                    AsyncValue.ready(f.value + state.user)
                else -> f
            }
        ),
        listOf(Command.async("toggle_follow") { FollowService.toggle(props.id) })
    )

fun handle_info(msg: AsyncResult<"toggle_follow", FollowResult>, state: UserProfileState): UserProfileState =
    when (msg) {
        is Ok -> state.copy(isFollowing = msg.value.isFollowing, followPending = false)
        is Err -> state.copy(
            isFollowing = !state.isFollowing,  // Revert optimistic update
            followPending = false
        )
    }

---

<div class="profile-page">
    <div class="profile-page__header">
        <Avatar src={state.user.avatarUrl} alt={state.user.name} size={.xl} />
        <div class="profile-page__meta">
            <h1>{ state.user.name }</h1>
            <p class="profile-page__bio">{ state.user.bio }</p>
            <div class="profile-page__stats">
                <span>
                    { when (state.followers) {
                        is AsyncValue.Ready -> state.followers.value.size.toString()
                        else -> "—"
                    } } followers
                </span>
                <span>
                    { when (state.posts) {
                        is AsyncValue.Ready -> state.posts.value.size.toString()
                        else -> "—"
                    } } posts
                </span>
            </div>
        </div>
        <button
            class={"btn " + if (state.isFollowing) "btn--secondary" else "btn--primary"}
            onClick={handleFollow}
            disabled={state.followPending}
            aria-busy={state.followPending}
        >
            { when {
                state.followPending -> "..."
                state.isFollowing   -> "Unfollow"
                else                -> "Follow"
            } }
        </button>
    </div>

    <section class="profile-page__posts">
        <h2>Posts</h2>
        { when (state.posts) {
            is AsyncValue.Loading -> <PostGridSkeleton count={6} />
            is AsyncValue.Error   -> <p class="error">{ state.posts.message }</p>
            is AsyncValue.Ready when state.posts.value.isEmpty() -> (
                <p class="empty-state">No posts yet.</p>
            )
            is AsyncValue.Ready   -> (
                <div class="post-grid">
                    {for post in state.posts.value}
                        <PostCard key={post.id} post={post} />
                    {/for}
                </div>
            )
        } }
    </section>
</div>
```

---

## 11.9 — PubSub and Real-Time

### The Translation: `useContext` + WebSocket → PubSub + `handle_info`

React's pattern for real-time data involves creating a WebSocket connection, wrapping its state in a Context, and consuming that context in components that need live data. This requires significant boilerplate: the connection management, the message routing, the reconnection logic, the context re-rendering.

In aKt, real-time data is just a process message. Components are already processes. They already handle messages via `handle_info`. PubSub is already part of the BEAM runtime (via `Phoenix.PubSub` or `Registry`). The infrastructure for real-time is not special-cased — it is the standard process model applied to UI.

### Subscribing to Topics

```kotlin
@LiveComponent
props NotificationCenterProps {
    val userId: String
}

data class NotificationCenterState(
    val notifications: List<Notification> = emptyList(),
    val unreadCount: Int = 0
)

fun mount(props: NotificationCenterProps): Pair<NotificationCenterState, List<Command>> =
    Pair(
        NotificationCenterState(),
        listOf(
            Command.async("load_notifications") {
                NotificationService.getUnread(props.userId)
            },
            // Subscribe to the user's notification topic
            Command.subscribe("notifications:${props.userId}")
        )
    )

fun handle_info(msg: AsyncResult<"load_notifications", List<Notification>>, state: NotificationCenterState): NotificationCenterState =
    state.copy(
        notifications = msg.value,
        unreadCount = msg.value.count { !it.read }
    )

// Handles PubSub messages on "notifications:{userId}"
fun handle_info(msg: NewNotification, state: NotificationCenterState): NotificationCenterState =
    state.copy(
        notifications = listOf(msg.notification) + state.notifications,
        unreadCount = state.unreadCount + 1
    )

fun handle_info(msg: NotificationRead, state: NotificationCenterState): NotificationCenterState =
    state.copy(
        notifications = state.notifications.map {
            if (it.id == msg.notificationId) it.copy(read = true) else it
        },
        unreadCount = maxOf(0, state.unreadCount - 1)
    )

fun handleMarkRead(notifId: String, state: NotificationCenterState): Pair<NotificationCenterState, List<Command>> =
    Pair(
        state.copy(
            notifications = state.notifications.map {
                if (it.id == notifId) it.copy(read = true) else it
            },
            unreadCount = maxOf(0, state.unreadCount - 1)
        ),
        listOf(Command.run { NotificationService.markRead(notifId) })
    )
```

`Command.subscribe(topic)` subscribes the component process to the PubSub topic. Messages broadcast on that topic are delivered to the component's `handle_info`. The subscription is automatically removed when the component process terminates.

Multiple subscriptions are supported:

```kotlin
fun mount(props: DashboardProps): Pair<DashboardState, List<Command>> =
    Pair(
        DashboardState(),
        listOf(
            Command.subscribe("metrics:global"),
            Command.subscribe("alerts:${props.orgId}"),
            Command.subscribe("user:${props.userId}")
        )
    )
```

### Broadcasting from Services

Any server-side code can broadcast to a PubSub topic. The message must be a type that has a `handle_info` handler registered in the subscribing component:

```kotlin
// In a Ping controller
@RestController
class NotificationController {
    @Post("/notifications/send")
    fun sendNotification(req: PingConn): PingConn {
        val notification = req.body<NotificationRequest>()
        val saved = NotificationService.create(notification)

        // Broadcast to all components subscribed to this user's topic
        PubSub.broadcast("notifications:${notification.userId}", NewNotification(saved))

        return req.json(saved)
    }
}

// In a background service
@Service
class MetricsCollector : GenServer<MetricsState, MetricsCall, MetricsCast> {
    override fun handleCast(msg: MetricsCast.CollectMetrics, state: MetricsState): Reply<MetricsState, MetricsCast> {
        val metrics = collectSystemMetrics()
        PubSub.broadcast("metrics:global", MetricsUpdated(metrics))
        return noReply(state.copy(lastCollected = metrics))
    }
}
```

`PubSub.broadcast` is typed: the message type must implement the `PubSubMessage` interface, and the compiler can verify that at least one subscriber type handles the message (though this check is opt-in via `@StrictPubSub`).

### Presence

Presence tracks which users are currently connected and viewing a particular resource. aKt provides `Presence` as a first-class API built on Phoenix.Presence:

```kotlin
@LiveComponent
props DocumentEditorProps {
    val documentId: String
    val session: Session
}

data class EditorState(
    val document: Document,
    val content: String,
    val presentUsers: List<PresenceUser> = emptyList(),
    val cursors: Map<String, CursorPosition> = emptyMap()
)

suspend fun loadData(props: DocumentEditorProps): EditorState {
    val doc = DocumentService.getById(props.documentId) ?: throw NotFoundException()
    return EditorState(document = doc, content = doc.content)
}

fun mount(props: DocumentEditorProps, initialState: EditorState): Pair<EditorState, List<Command>> =
    Pair(
        initialState,
        listOf(
            Command.subscribe("document:${props.documentId}"),
            // Track presence: announce this user is viewing the document
            Command.trackPresence(
                topic = "document:${props.documentId}",
                key = props.session.userId,
                meta = PresenceMeta(
                    name = props.session.user.name,
                    avatarUrl = props.session.user.avatarUrl,
                    joinedAt = Instant.now()
                )
            )
        )
    )

// Presence join/leave events
fun handle_info(msg: PresenceDiff, state: EditorState): EditorState =
    state.copy(presentUsers = Presence.list(msg))

// Real-time document changes from other users
fun handle_info(msg: DocumentChange, state: EditorState): EditorState =
    state.copy(content = msg.content)

// Cursor position updates from other users
fun handle_info(msg: CursorMoved, state: EditorState): EditorState =
    state.copy(cursors = state.cursors + (msg.userId to msg.position))

fun handleContentChange(event: InputEvent, state: EditorState, props: DocumentEditorProps): Pair<EditorState, List<Command>> =
    Pair(
        state.copy(content = event.value),
        listOf(
            Command.async("save_document") { DocumentService.update(props.documentId, event.value) },
            Command.broadcast("document:${props.documentId}", DocumentChange(
                content = event.value,
                userId = props.session.userId,
                timestamp = Instant.now()
            ))
        )
    )
```

`Command.trackPresence` registers the component in the Presence system for the given topic with the given key and metadata. When any user joins or leaves the topic, all subscribers receive a `PresenceDiff` message.

`Presence.list(diff)` computes the current list of present users from a `PresenceDiff` message.

### Complete Real-Time Example: Collaborative Todo List

```kotlin
// pages/todos/[listId].akt

import kore.akt.*
import kore.akt.live.*
import kore.akt.presence.*
import myapp.services.*
import myapp.domain.*

@LiveComponent
props TodoListProps {
    val listId: String
    val session: Session
}

data class TodoItem(
    val id: String,
    val text: String,
    val completed: Boolean,
    val createdBy: String,
    val assignedTo: String? = null
)

data class TodoListState(
    val todos: List<TodoItem> = emptyList(),
    val newTodoText: String = "",
    val presentUsers: List<PresenceUser> = emptyList(),
    val loading: Boolean = true,
    val editingId: String? = null,
    val editText: String = ""
)

suspend fun loadData(props: TodoListProps): TodoListState {
    val todos = TodoService.getByList(props.listId)
    return TodoListState(todos = todos, loading = false)
}

fun mount(props: TodoListProps, initialState: TodoListState): Pair<TodoListState, List<Command>> =
    Pair(
        initialState,
        listOf(
            Command.subscribe("todolist:${props.listId}"),
            Command.trackPresence(
                topic = "todolist:${props.listId}",
                key = props.session.userId,
                meta = PresenceMeta(
                    name = props.session.user.name,
                    avatarUrl = props.session.user.avatarUrl
                )
            )
        )
    )

// PubSub handlers
fun handle_info(msg: PresenceDiff, state: TodoListState): TodoListState =
    state.copy(presentUsers = Presence.list(msg))

fun handle_info(msg: TodoCreated, state: TodoListState): TodoListState =
    if (state.todos.none { it.id == msg.todo.id }) {
        state.copy(todos = state.todos + msg.todo)
    } else state

fun handle_info(msg: TodoCompleted, state: TodoListState): TodoListState =
    state.copy(todos = state.todos.map {
        if (it.id == msg.todoId) it.copy(completed = msg.completed) else it
    })

fun handle_info(msg: TodoDeleted, state: TodoListState): TodoListState =
    state.copy(todos = state.todos.filter { it.id != msg.todoId })

fun handle_info(msg: TodoUpdated, state: TodoListState): TodoListState =
    state.copy(todos = state.todos.map {
        if (it.id == msg.todo.id) msg.todo else it
    })

// Event handlers
fun handleNewTodoInput(event: InputEvent, state: TodoListState): TodoListState =
    state.copy(newTodoText = event.value)

fun handleAddTodo(state: TodoListState, props: TodoListProps): Pair<TodoListState, List<Command>> {
    val text = state.newTodoText.trim()
    if (text.isBlank()) return Pair(state, emptyList())

    val newTodo = TodoItem(
        id = UUID.random(),
        text = text,
        completed = false,
        createdBy = props.session.userId
    )
    return Pair(
        state.copy(newTodoText = "", todos = state.todos + newTodo),
        listOf(
            Command.async("save_todo") { TodoService.create(props.listId, newTodo) },
            Command.broadcast("todolist:${props.listId}", TodoCreated(newTodo))
        )
    )
}

fun handleToggle(todoId: String, state: TodoListState, props: TodoListProps): Pair<TodoListState, List<Command>> {
    val todo = state.todos.find { it.id == todoId } ?: return Pair(state, emptyList())
    val completed = !todo.completed
    return Pair(
        state.copy(todos = state.todos.map {
            if (it.id == todoId) it.copy(completed = completed) else it
        }),
        listOf(
            Command.async("toggle_todo_$todoId") { TodoService.setCompleted(todoId, completed) },
            Command.broadcast("todolist:${props.listId}", TodoCompleted(todoId, completed))
        )
    )
}

fun handleDelete(todoId: String, state: TodoListState, props: TodoListProps): Pair<TodoListState, List<Command>> =
    Pair(
        state.copy(todos = state.todos.filter { it.id != todoId }),
        listOf(
            Command.async("delete_todo_$todoId") { TodoService.delete(todoId) },
            Command.broadcast("todolist:${props.listId}", TodoDeleted(todoId))
        )
