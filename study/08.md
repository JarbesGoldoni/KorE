# Session 10: Ping — The BEAM-Native Web Framework

---

## 10.1 — Philosophy & Design Principles

Ping is not a port of Spring MVC. It is not Phoenix with Kotlin syntax pasted over it. It is a web framework designed from a single governing constraint: Spring developers must feel at home in the first five minutes, and never feel lied to afterward.

That constraint produces genuine tension. Spring's mental model is built on three pillars that do not exist on the BEAM: thread-local state (SecurityContext, RequestContextHolder), a DI container that owns object lifecycle, and a defensive error model where exceptions are caught and converted at every boundary. Ping must look like it shares those pillars while running on a runtime that has none of them.

The resolution is not to fake it. Faking it produces frameworks that are confusing to both audiences. Instead, Ping adopts a mapping principle: Spring vocabulary, BEAM execution model. `@RestController` is a real annotation. What it compiles to is a BEAM module with exported functions, not a Spring bean. The annotation is familiar. The semantics are honest.

The five core principles follow from this.

---

### Principle 1: The Pipeline Is the Framework

**Spring model:** A DispatcherServlet sits at the center. Filters run before it. HandlerInterceptors run inside it. Exception resolvers clean up after it. The flow is implicit — you declare components, and the container wires them into an execution order you must read documentation to understand.

**Phoenix model:** Everything is a Plug. The pipeline is explicit and composable. There is no central dispatcher — there is a function from `Conn` to `Conn`, composed from smaller functions.

**Ping's choice:** Ping adopts the Plug model wholesale. Every HTTP request is a `PingConn` value. Every middleware is a function `(PingConn) -> PingConn`. The router is middleware. The controller is middleware. Authentication is middleware. The entire framework is one pipeline.

Why this over Spring's model: the pipeline is auditable. You can read a Ping application's `router {}` block and know exactly what runs on every request, in what order, with no implicit container magic. This is better for correctness, better for debugging, and better for BEAM's process-per-request model where there is no shared dispatcher to protect.

Why this over raw Plug: Ping adds Spring-familiar annotations for the leaf nodes of the pipeline (controllers, exception handlers, validators) so that developers writing business logic never see the pipeline machinery directly. The pipeline is the framework's concern. Controllers are the developer's concern.

---

### Principle 2: Every Request Is a Process

**Spring model:** Requests are handled by threads from a pool. Thread-local storage (SecurityContext, RequestAttributes) provides per-request isolation. The thread pool is a scarce resource — blocking a thread blocks a request slot.

**BEAM model:** Processes are cheap. A BEAM process costs ~2KB of heap. The scheduler is preemptive. Blocking in one process does not affect other processes. There is no thread-local storage because there is no thread — there is a process, and the process's heap is its context.

**Ping's choice:** Each HTTP request is handled by a dedicated BEAM process, spawned by the connection acceptor and linked to the endpoint supervisor. Per-request state (authentication, assigns, parsed body) lives in the process dictionary or, preferably, in `PingConn` itself passed through the pipeline. There is no global SecurityContext. There is no thread-local anything.

Why this matters for the developer: the mental model simplifies. You cannot accidentally share state between requests by forgetting to clear a ThreadLocal. You cannot deadlock on a shared resource because processes do not share memory. Crash isolation is structural — one request process crashing does not affect any other request.

Why this is better than hiding it: Ping surfaces this. The developer guide says "each request is a process." The supervision tree is visible. This is not an implementation detail to be ashamed of — it is the reason Ping can handle millions of concurrent connections on modest hardware.

---

### Principle 3: Let It Crash at the Request Boundary, Defend at the Domain Boundary

**Spring model:** Defensive programming throughout. Every service method catches exceptions. `@ExceptionHandler` methods exist at multiple levels. The implicit assumption is that exceptions are normal control flow and must be handled everywhere.

**BEAM model:** "Let it crash." Processes crash, supervisors restart them. Error handling is for expected errors only — unexpected failures are left to the supervisor.

**Ping's choice:** A hybrid that is honest about where each philosophy applies.

At the request level: let it crash. If a controller process crashes with an unhandled exception, the endpoint supervisor catches it at the process link boundary, logs it, and the client receives a 500. No other request is affected. The crashed process is gone — nothing to clean up.

At the domain boundary: use `Ok`/`Err` explicitly. A `UserService` that might fail to find a user returns `Ok<User>` or `Err<NotFoundError>`. This is not a crash — it is a typed expected-failure path. The controller pattern-matches on it and returns the appropriate HTTP response.

The rule: if it can happen in normal operation, model it with `Ok`/`Err`. If it should never happen (programmer error, corrupted state, unreachable code), let it crash.

This matches what experienced Spring developers already know they should do, but the BEAM enforces it structurally rather than by convention.

---

### Principle 4: The Supervision Tree Is Your Application

**Spring model:** The ApplicationContext is your application. Beans are registered in it. Startup order is inferred from dependencies. Shutdown hooks are registered implicitly. The container manages lifecycle.

**BEAM model:** The OTP application and its supervision tree is your application. Processes are started in dependency order by the supervisor. Shutdown is orderly because the supervisor shuts down children in reverse start order. Lifecycle is explicit.

**Ping's choice:** Ping generates an OTP supervision tree from your application's annotations and configuration. `@PingApplication` generates a top-level supervisor. `@Service` annotations register GenServers under an application supervisor. The supervision tree is visible, inspectable via `:observer`, and configurable.

The developer does not need to write OTP boilerplate. But the boilerplate that gets generated is not hidden — it is emitted as readable KorE source that can be overridden. The supervision tree is a first-class concept in Ping, not an implementation detail.

---

### Principle 5: Annotations Describe; DSLs Compose

**Spring model:** Annotations describe everything — controllers, endpoints, beans, validation, security. DSLs are available but optional (Spring Security DSL, WebFlux functional endpoints). The annotation-heavy style can make code feel like configuration rather than logic.

**Phoenix model:** DSLs compose everything — pipelines, routers, channels. Annotations are absent. The style is more functional but less familiar to Java/Kotlin developers.

**Ping's choice:** Annotations describe leaf-node declarations (what this function handles, what this class is, what this parameter means). DSLs compose structural elements (how the router is organized, how middleware pipelines are assembled, how the supervision tree is configured).

The boundary: if you are declaring something that is a single unit of work (a controller action, a validation constraint, a service), use an annotation. If you are composing multiple units into a structure (a router, a pipeline, a supervisor), use a DSL. This keeps controller code clean and readable while keeping application structure explicit and auditable.

---

## 10.2 — The Request Pipeline: PingConn and Middleware

### The PingConn Data Class

`PingConn` is the carrier type for the entire HTTP request-response cycle. It is immutable — every middleware transformation returns a new `PingConn`. It is passed explicitly through every stage of the pipeline. There is no implicit request context.

```kotlin
data class PingConn(
    // Request fields — populated before pipeline execution
    val method: HttpMethod,
    val path: String,
    val pathParams: Map<String, String>,
    val queryParams: Map<String, List<String>>,
    val headers: Headers,
    val body: Body,
    val host: String,
    val port: Int,
    val scheme: Scheme,
    val remoteIp: String,

    // Response fields — built up through the pipeline
    val status: Int = 200,
    val respHeaders: Headers = Headers.empty(),
    val respBody: RespBody = RespBody.Empty,

    // Pipeline control
    val halted: Boolean = false,

    // Extensible per-request state — typed access via assigns()
    val assigns: Map<String, Any?> = emptyMap(),

    // Framework-private state — not for application code
    val private: Map<String, Any?> = emptyMap(),

    // Adapter reference — the underlying BEAM socket/connection
    val adapter: ConnectionAdapter
)
```

`PingConn` is a KorE `data class`, which means it maps to an Erlang map at the BEAM level (the default) rather than a record. This is deliberate — the `assigns` field is open-ended, and map semantics are correct here. The overhead of map operations on a short-lived per-request value is acceptable and benchmarks confirm it.

Key design decisions in `PingConn`:

**`assigns` is `Map<String, Any?>`** rather than a typed map. The type safety comes from typed accessor extensions:

```kotlin
// Framework provides typed assign accessors
fun PingConn.assign(key: String, value: Any?): PingConn =
    copy(assigns = assigns + (key to value))

// Application code defines typed accessors
val PingConn.currentUser: User?
    get() = assigns["currentUser"] as? User
```

This is exactly how Plug.Conn works. The alternative — a parameterized `PingConn<A>` where `A` is the assigns type — was considered and rejected. It would make middleware composition painful: every middleware that adds a key would change the type, making pipeline types unwieldy. `Dynamic`-style typed extraction is the right tradeoff here.

**`halted` is a field, not an exception.** When a middleware halts the pipeline (e.g., authentication fails), it returns `conn.halt()` with a response set. Subsequent middlewares check `conn.halted` and short-circuit. No exception is thrown. This is the Plug model and it is correct — halting is not an error, it is a normal control flow path (return a 401, stop processing).

**`private` is for framework internals.** Adapters, raw socket references, and routing metadata live here. Application code must not read or write to `private` directly. The compiler can enforce this via a `@Internal` annotation on the field.

**`body`** is a sealed type:

```kotlin
sealed class Body {
    object Unread : Body()
    data class Raw(val bytes: ByteArray) : Body()
    data class Parsed<T>(val value: T) : Body()
    object TooLarge : Body()
}
```

Body reading is lazy. The body is not read until a middleware explicitly reads it. This prevents double-reading and allows middlewares early in the pipeline to make routing decisions before paying the cost of body parsing.

**BEAM representation:** At the BEAM level, `PingConn` is an Erlang map with atom keys. The compiler generates a module `'KorE.Ping.Conn'` with functions corresponding to `copy()` operations. Updates are map updates — O(log n) for a small fixed-key map, which in practice means one or two BEAM operations.

---

### The Middleware Interface

```kotlin
fun interface Middleware {
    fun call(conn: PingConn): PingConn
}
```

`fun interface` means any function `(PingConn) -> PingConn` is a valid middleware. This is the simplest possible interface. Middleware is a function.

The pipeline is a list of middlewares composed left-to-right:

```kotlin
typealias Pipeline = List<Middleware>

fun Pipeline.run(conn: PingConn): PingConn =
    fold(conn) { c, middleware ->
        if (c.halted) c else middleware.call(c)
    }
```

The `halted` check in `fold` implements short-circuit semantics without exceptions. This is a hot path — the compiler should inline small middleware implementations.

**Async middleware:** Some middleware needs to perform async work (e.g., reading from a cache). The synchronous signature `(PingConn) -> PingConn` handles this correctly on the BEAM because process blocking is cheap. A middleware that calls `GenServer.call(cache, ...)` blocks its process, not a thread. The scheduler handles other processes during the wait. No async/await machinery is needed.

This is a significant departure from Spring's `HandlerInterceptor`, which runs on a thread pool and where blocking is costly. On the BEAM, the synchronous pipeline is the right model. Ping does not expose async middleware variants for this reason — the BEAM's scheduler makes them unnecessary.

---

### Comparison to Spring and Phoenix

**Spring `HandlerInterceptor`:**
- Runs in two phases: `preHandle` (before controller) and `postHandle` (after controller)
- Returns a boolean from `preHandle` to halt — no response is set in the interceptor itself; you call `response.sendError()` as a side effect
- Operates on mutable `HttpServletRequest`/`HttpServletResponse` objects
- Cannot easily compose interceptors into named pipelines

**Spring `Filter` (servlet filter):**
- More powerful than interceptor — wraps the entire DispatcherServlet
- Operates on `FilterChain.doFilter()` continuation style
- Mutable, imperative, harder to reason about

**Phoenix `Plug` protocol:**
- Exactly the same model as Ping's `Middleware`
- A Plug is `call(conn, opts) :: conn`
- Pipelines are composed with `plug/2` macro
- Halting is `Plug.Conn.halt(conn)`

Ping's `Middleware` is Phoenix's Plug with KorE syntax. The semantic model is identical. The difference is that Phoenix Plugs are often module-level (a module implements the Plug behaviour), while Ping Middlewares can be lambdas, function references, or class implementations. This makes Ping middleware more composable in a functional style.

---

### Declaring Middleware: Syntax Options

**Option A: Class-based (Spring-familiar)**

```kotlin
class LoggingMiddleware : Middleware {
    override fun call(conn: PingConn): PingConn {
        val start = System.monotonic()
        val result = conn  // logging before — pass through
        // Note: cannot log after in this model without wrapping
        return result.assign("requestStart", start)
    }
}
```

The limitation is that class-based middleware cannot observe the response without restructuring as a "before/after" pair.

**Option B: Functional with wrap semantics**

```kotlin
val loggingMiddleware: Middleware = Middleware { conn ->
    val start = BEAMTime.monotonic()
    conn.assign("requestStart", start)
}

// A wrapper middleware that observes both request and response
fun loggingWrapper(inner: Middleware): Middleware = Middleware { conn ->
    val start = BEAMTime.monotonic()
    val result = inner.call(conn)
    val elapsed = BEAMTime.diff(start, BEAMTime.monotonic(), .millisecond)
    Logger.info("${conn.method} ${conn.path} → ${result.status} (${elapsed}ms)")
    result
}
```

**Option C: `@Middleware` annotation on a class, compiler generates wrapper**

```kotlin
@Middleware
class LoggingMiddleware {
    @Before
    fun before(conn: PingConn): PingConn =
        conn.assign("requestStart", BEAMTime.monotonic())

    @After
    fun after(conn: PingConn, result: PingConn): PingConn {
        val elapsed = BEAMTime.diff(
            conn.assigns["requestStart"] as Long,
            BEAMTime.monotonic(),
            .millisecond
        )
        Logger.info("${conn.method} ${conn.path} → ${result.status} (${elapsed}ms)")
        return result
    }
}
```

**Recommendation: Option B (functional) for framework middleware, Option C (annotation) for application middleware.**

The functional form is the primitive. The annotation form is syntax sugar for the common before/after pattern. The compiler desugars `@Before`/`@After` into the wrapper composition. This gives Spring developers a familiar annotation model for writing middleware while keeping the framework's internals clean and functional.

---

### Complete Example: Logging and Auth Middleware

```kotlin
// logging.kore
@Middleware
class RequestLogger {
    @Before
    fun recordStart(conn: PingConn): PingConn =
        conn.assign("requestStart", BEAMTime.monotonic())

    @After
    fun logResult(conn: PingConn, result: PingConn): PingConn {
        val start = conn.assigns["requestStart"] as Long
        val elapsed = BEAMTime.diff(start, BEAMTime.monotonic(), .millisecond)
        val level = if (result.status >= 500) .error else .info
        Logger.log(level, "[Ping] ${conn.method} ${conn.path} → ${result.status} in ${elapsed}ms")
        return result
    }
}

// auth.kore
class AuthMiddleware(
    private val jwtService: JwtService
) : Middleware {
    override fun call(conn: PingConn): PingConn {
        val token = conn.headers.get("Authorization")
            ?.removePrefix("Bearer ")
            ?: return conn
                .putStatus(401)
                .json(ErrorResponse("Missing authorization token"))
                .halt()

        return when (val result = jwtService.verify(token)) {
            is Ok -> conn.assign("currentUser", result.value)
            is Err -> conn
                .putStatus(401)
                .json(ErrorResponse("Invalid token: ${result.error.message}"))
                .halt()
        }
    }
}

// pipeline.kore — composing into named pipelines
router {
    pipeline(.browser) {
        plug(RequestLogger)
        plug(SessionMiddleware)
        plug(CsrfProtection)
    }

    pipeline(.api) {
        plug(RequestLogger)
        plug(JsonParser)
        plug(AuthMiddleware)
    }

    scope("/api/v1") {
        pipe_through(.api)
        resources("/users", UserController)
        resources("/posts", PostController)
    }

    scope("/") {
        pipe_through(.browser)
        get("/", HomeController::index)
    }
}
```

---

## 10.3 — Routing DSL

The router is the most visible API surface in a web framework. It is where the application's structure is declared. Every significant web framework has a different answer to how routing should be expressed. Ping must make a choice that is readable to Spring developers, generates efficient BEAM code, and is extensible without becoming a configuration language.

---

### Option A: Annotation-Driven (Spring Style)

```kotlin
@RestController
@RequestMapping("/api/v1/users")
class UserController(private val userService: UserService) {

    @GetMapping("/{id}")
    fun getUser(@PathVariable id: String): UserResponse {
        return userService.findById(id)
            .map { UserResponse.from(it) }
            .orElseThrow { NotFoundException("User $id not found") }
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun createUser(@Valid @RequestBody request: CreateUserRequest): UserResponse {
        return userService.create(request)
            |> UserResponse.from(_)
    }

    @PutMapping("/{id}")
    fun updateUser(
        @PathVariable id: String,
        @Valid @RequestBody request: UpdateUserRequest
    ): UserResponse {
        return userService.update(id, request)
            .map { UserResponse.from(it) }
            .orElseThrow { NotFoundException("User $id not found") }
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteUser(@PathVariable id: String) {
        userService.delete(id)
    }
}
```

**What the compiler must generate:**

Each annotated function becomes a clause in a pattern-matched BEAM function. The `@RequestMapping` and `@GetMapping` annotations are compiled to routing table entries. At the BEAM level, the router is a set of pattern-matched function clauses in a generated module `'KorE.Router'`:

```erlang
% Generated Erlang Abstract Format (conceptual)
route(<<"GET">>, [<<"api">>, <<"v1">>, <<"users">>, Id], Conn) ->
    'KorE.UserController':get_user(Conn#{path_params => #{<<"id">> => Id}});
route(<<"POST">>, [<<"api">>, <<"v1">>, <<"users">>], Conn) ->
    'KorE.UserController':create_user(Conn);
```

**BEAM module structure:** One BEAM module per controller class. The router module dispatches to controller modules. Controller modules export one function per annotated method.

**Tradeoffs:**
- Familiar to Spring developers — zero learning curve for the annotation style
- Controller code is self-contained — you can read a controller file and know what routes it handles
- The global route table is not visible in one place — you must read all controllers to understand routing
- Circular dependency risk: routes defined in controllers, but controllers may depend on the router for URL generation
- Annotation processing is a compile-time concern — errors surface late if not carefully implemented
- Overlapping routes across controllers are hard to detect without running the application

---

### Option B: Builder DSL (Phoenix/Gleam Style)

```kotlin
// router.kore
val router = router {
    pipeline(.browser) {
        plug(RequestLogger)
        plug(SessionMiddleware)
        plug(FetchSession)
        plug(ProtectFromForgery)
    }

    pipeline(.api) {
        plug(RequestLogger)
        plug(JsonParser)
        plug(AuthMiddleware)
    }

    scope("/api/v1") {
        pipe_through(.api)

        scope("/users") {
            get("/", UserController::index)
            post("/", UserController::create)
            get("/{id}", UserController::show)
            put("/{id}", UserController::update)
            delete("/{id}", UserController::delete)
        }

        scope("/posts") {
            get("/", PostController::index)
            get("/{id}", PostController::show)
            post("/", PostController::create)
        }
    }

    scope("/") {
        pipe_through(.browser)
        get("/", HomeController::index)
        get("/about", HomeController::about)
    }
}
```

**What the compiler must generate:**

The router DSL is evaluated at compile time (or at application start as a macro-expanded constant). The result is a routing trie. At the BEAM level:

```erlang
% Generated: single routing module with pattern matching
route(#{method := <<"GET">>, path := [<<"api">>, <<"v1">>, <<"users">>]} = Conn) ->
    run_pipeline([log, json_parser, auth], Conn,
        fun(C) -> 'KorE.UserController':index(C) end);
route(#{method := <<"GET">>, path := [<<"api">>, <<"v1">>, <<"users">>, Id]} = Conn) ->
    run_pipeline([log, json_parser, auth], Conn,
        fun(C) -> 'KorE.UserController':show(C#{path_params => #{id => Id}}) end);
```

**BEAM module structure:** A single `'KorE.Router'` module contains all routes as pattern-matched clauses. Pipeline execution is inlined or called as a function. Controller modules export handler functions without any routing metadata.

**Tradeoffs:**
- All routes visible in one file — the router file is the application's HTTP contract
- Pipeline assignment is explicit and visible — no implicit ordering
- Compile-time route conflict detection is straightforward
- Controllers become pure functions — no routing annotations, easier to test in isolation
- Less familiar to Spring developers — requires learning the DSL
- More boilerplate for large applications with many routes
- Controller files do not self-document their routes

---

### Option C: Hybrid — DSL Router + Annotation Controllers

The router DSL owns structure and pipeline assignment. Annotation-based controllers own their path segments relative to a `resources()` or `scope()` declaration.

```kotlin
// router.kore — DSL for structure
router {
    pipeline(.api) {
        plug(RequestLogger)
        plug(JsonParser)
        plug(AuthMiddleware)
    }

    scope("/api/v1") {
        pipe_through(.api)
        resources("/users", UserController)       // expands all CRUD routes
        resources("/posts", PostController, only = [.index, .show])
        get("/health", HealthController::check)
    }
}

// user_controller.kore — annotations for handler metadata
@RestController
class UserController(private val userService: UserService) {

    @Get("/{id}")
    fun show(@PathVariable id: String): UserResponse {
        return when (val result = userService.findById(id)) {
            is Ok -> result.value |> UserResponse.from(_)
            is Err -> throw NotFoundException(result.error)
        }
    }

    @Post
    @ResponseStatus(201)
    fun create(@Valid @RequestBody request: CreateUserRequest): UserResponse {
        return when (val result = userService.create(request)) {
            is Ok -> result.value |> UserResponse.from(_)
            is Err -> throw ValidationException(result.error)
        }
    }

    @Put("/{id}")
    fun update(
        @PathVariable id: String,
        @Valid @RequestBody request: UpdateUserRequest
    ): UserResponse {
        return when (val result = userService.update(id, request)) {
            is Ok -> result.value |> UserResponse.from(_)
            is Err -> throw NotFoundException(result.error)
        }
    }

    @Delete("/{id}")
    @ResponseStatus(204)
    fun delete(@PathVariable id: String) {
        userService.delete(id)
            .orThrow { NotFoundException(it) }
    }
}
```

**What the compiler must generate:**

1. The router DSL is analyzed at compile time. `resources("/users", UserController)` expands to the standard seven RESTful routes.
2. Each `@Get`, `@Post`, `@Put`, `@Delete` annotation on `UserController` is resolved against the `resources` expansion to bind path segments.
3. The compiler validates that all `resources` routes have corresponding annotated methods. Missing methods produce warning `KW0201: UserController has no handler for DELETE /users/{id}`.
4. The generated routing module merges router DSL structure with controller annotations.

**BEAM module structure:** The same as Option B — a single router module with pattern-matched clauses. Controller modules are plain BEAM modules with exported handler functions.

---

### Recommendation: Option C (Hybrid)

The hybrid approach is the right answer for Ping, for three concrete reasons:

**1. Structure and behavior belong in different places.** Route structure (which paths exist, which pipelines they use, how they group) is an application-level concern. Handler behavior (what this function does when called) is a controller-level concern. Separating them into router DSL and controller annotations matches the actual conceptual separation.

**2. Spring familiarity where it matters.** Spring developers spend most of their time in controllers, not routers. Annotation-driven controllers feel immediately familiar. The router DSL is a smaller surface area to learn.

**3. The compiler can validate completeness.** When `resources("/users", UserController)` is declared in the router, the compiler knows exactly which methods are expected. Missing handler annotations are compile-time warnings. Route conflicts are compile-time errors. This is not possible with pure annotation-driven routing where routes are scattered across files.

The `resources()` macro is particularly valuable — it expands to the standard RESTful convention and documents intent clearly. A Spring developer who has used `@RequestMapping` conventions will recognize this immediately.

---

### Path Parameter Syntax

Three options exist for path parameter syntax:

| Style | Example | Source |
|-------|---------|--------|
| Curly brace | `{id}` | Spring, OpenAPI |
| Colon | `:id` | Express.js, Rails |
| Angle bracket | `<id>` | Gleam |

**Decision: `{id}` (curly brace).**

It matches Spring MVC, matches OpenAPI specification format (which Ping generates automatically), and is already familiar to the target audience. `:id` is Rails/Express-style and implies a different audience. `<id>` is novel without benefit.

```kotlin
get("/users/{id}", UserController::show)
get("/orgs/{orgId}/repos/{repoId}", RepoController::show)
```

Path parameters are extracted into `conn.pathParams: Map<String, String>` and bound to `@PathVariable` annotated controller parameters.

---

### Query Parameters

Query parameters are available via `conn.queryParams: Map<String, List<String>>`. The `List<String>` handles repeated parameters (`?tag=a&tag=b`). Controller methods access them via `@RequestParam`:

```kotlin
@Get
fun index(
    @RequestParam(defaultValue = "1") page: Int,
    @RequestParam(defaultValue = "20") pageSize: Int,
    @RequestParam(required = false) search: String?
): PagedResponse<UserResponse> {
    return userService.list(page, pageSize, search)
}
```

The `@RequestParam` annotation drives compiler-generated extraction code that reads from `conn.queryParams`, applies type coercion, applies defaults, and raises a 400 if a required parameter is missing or cannot be coerced.

---

### Wildcard Routes

```kotlin
// Matches /files/path/to/any/file.txt
get("/files/{*path}", FileController::serve)

// Matches any path not matched by earlier routes (must be last)
get("/{*path}", NotFoundController::handle)
```

The `{*name}` syntax captures everything from that segment onward as a single string. At the BEAM level this is a list of path segments joined with `/`. The wildcard route must appear last in its scope — the compiler enforces this ordering and emits error `KE2001: Wildcard route must be the last route in its scope` otherwise.

---

### Route Groups and Scopes

Scopes compose pipelines and path prefixes:

```kotlin
router {
    pipeline(.api) { plug(JsonParser); plug(AuthMiddleware) }
    pipeline(.admin) { plug(JsonParser); plug(AuthMiddleware); plug(AdminRequired) }

    scope("/api/v1") {
        pipe_through(.api)

        // Nested scope inherits parent path prefix and pipeline
        scope("/admin") {
            pipe_through(.admin)  // adds to parent pipeline
            resources("/users", AdminUserController)
        }

        resources("/users", UserController)
    }
}
```

Pipeline composition in nested scopes is additive: a nested `pipe_through()` adds to the parent pipeline, it does not replace it. The compiled BEAM code for an admin route runs both `.api` and `.admin` middlewares in declaration order.

---

### Named Routes and URL Generation

Routes can be named for URL generation:

```kotlin
router {
    scope("/api/v1") {
        get("/users/{id}", UserController::show, name = "user_show")
        post("/users", UserController::create, name = "user_create")
    }
}
```

The compiler generates a `Routes` object with typed URL generation functions:

```kotlin
// Generated by compiler
object Routes {
    fun userShow(id: String): String = "/api/v1/users/$id"
    fun userCreate(): String = "/api/v1/users"
}

// Usage
val url = Routes.userShow(userId)
```

For `resources()` declarations, the generated names follow the `{resource}_{action}` convention: `userIndex`, `userShow`, `userCreate`, `userUpdate`, `userDelete`.

The `Routes` object is generated at compile time from the router DSL. URL generation functions are type-safe — `Routes.userShow(id)` requires a `String` argument matching the `{id}` path parameter. Mismatched argument count or type is a compile error.

---

### Constraint Routes

Routes can include guards that further constrain matches beyond path structure:

```kotlin
router {
    scope("/api/v1") {
        // Only matches if id looks like a UUID
        get("/users/{id}", UserController::show) {
            id matches Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
        }

        // Only matches if id is a positive integer
        get("/legacy/users/{id}", LegacyUserController::show) {
            id.toIntOrNull() != null
        }
    }
}
```

Constraints are compile-time predicates applied after path matching. At the BEAM level, they become guard clauses on the routing function:

```erlang
route(#{method := <<"GET">>, path := [<<"api">>, <<"v1">>, <<"users">>, Id]} = Conn)
  when re:run(Id, <<"[0-9a-f]{8}-...">>>) =/= nomatch ->
    ...
```

---

## 10.4 — Controllers and Request Handling

### The Request-Response Lifecycle

In Ping, the full request lifecycle is:

1. A connection is accepted by the endpoint supervisor's acceptor pool
2. A new BEAM process is spawned for the request
3. The acceptor sends the parsed HTTP request to the process
4. The process constructs a `PingConn` from the raw request
5. The router's pipeline runs on the `PingConn`
6. The matching controller function is called with the final `PingConn`
7. The controller returns a value (data class, explicit `PingConn`, or `Response`)
8. The response is serialized and sent back to the client
9. The request process exits normally (or abnormally — the supervisor handles it either way)

This is structurally different from Spring, where a thread from the DispatcherServlet's pool handles the request. In Spring, the request handler must not block for long because it holds a thread. In Ping, the request process can block freely — it is preempted by the scheduler and does not hold any shared resource.

---

### Controller Declaration

```kotlin
@RestController
class UserController(
    private val userService: UserService,
    private val cacheService: CacheService
) {
    // Handler methods here
}
```

`@RestController` in Ping compiles to a BEAM module. The constructor parameters are resolved via the DI system (see Section 10.5). Unlike Spring, `@RestController` does not imply a singleton bean — controllers are stateless modules, not stateful objects. The "constructor parameters" are resolved once at application start and become the module's static context.

---

### Parameter Binding

**Path variables:** Extracted from `conn.pathParams`, coerced to the declared type.

```kotlin
@Get("/{id}")
fun show(@PathVariable id: String): UserResponse { ... }

// With type coercion
@Get("/{orgId}/repos/{id}")
fun showRepo(
    @PathVariable orgId: Long,
    @PathVariable id: Long
): RepoResponse { ... }
```

Type coercion failures (e.g., `"abc"` cannot coerce to `Long`) produce a 400 response with error code `KE3001: Path variable type coercion failed`.

**Query parameters:** Extracted from `conn.queryParams`.

```kotlin
@Get
fun index(
    @RequestParam(defaultValue = "1") page: Int,
    @RequestParam(name = "page_size", defaultValue = "20") pageSize: Int,
    @RequestParam(required = false) q: String?
): PagedResponse<UserResponse> { ... }
```

**Request body:** The body is read and parsed by the `JsonParser` middleware before the controller is called. The `@RequestBody` annotation tells the compiler to extract the parsed body and bind it to the parameter.

```kotlin
@Post
@ResponseStatus(201)
fun create(@Valid @RequestBody request: CreateUserRequest): UserResponse { ... }
```

If body parsing fails (malformed JSON, wrong content type), the `JsonParser` middleware returns a 400 before the controller is called. The controller never sees a malformed body.

**Request headers:** Extracted from `conn.headers`.

```kotlin
@Get
fun show(
    @PathVariable id: String,
    @RequestHeader("X-Correlation-Id") correlationId: String?
): UserResponse { ... }
```

---

### Return Types

Controller functions can return several types. The compiler knows how to handle each:

**Data class (auto-serialized):**
```kotlin
@Get("/{id}")
fun show(@PathVariable id: String): UserResponse {
    return userService.findById(id).orThrow { NotFoundException(it) }
}
// Compiler generates: serialize(result) |> conn.json(200, _)
```

**`Ok`/`Err` (pattern matched by framework):**
```kotlin
@Get("/{id}")
fun show(@PathVariable id: String): Ok<UserResponse> | Err<DomainError> {
    return userService.findById(id).map { UserResponse.from(it) }
}
// Framework maps Ok → 200 JSON, Err → mapped error response
// Mapping is configured in the global exception handler (Section 10.6)
```

**Explicit `Response`:**
```kotlin
@Get("/{id}")
fun show(@PathVariable id: String): Response {
    return when (val result = userService.findById(id)) {
        is Ok -> Response.ok(UserResponse.from(result.value))
        is Err -> Response.notFound(ErrorBody.from(result.error))
    }
}
```

**`PingConn` (full control):**
```kotlin
@Get("/{id}")
fun show(@PathVariable id: String): PingConn {
    return when (val result = userService.findById(id)) {
        is Ok -> conn
            .putStatus(200)
            .putRespHeader("X-User-Version", result.value.version.toString())
            .json(UserResponse.from(result.value))
        is Err -> conn
            .putStatus(404)
            .json(ErrorBody.from(result.error))
    }
}
// conn is available in scope — injected by the compiler when return type is PingConn
```

When return type is `PingConn`, the compiler injects a `conn: PingConn` as an implicit first parameter. This is the one case where Ping does something implicit. It is necessary to avoid forcing developers to explicitly declare the conn parameter for every handler.

---

### `@ResponseStatus`

```kotlin
@Post
@ResponseStatus(201)
fun create(@RequestBody request: CreateUserRequest): UserResponse { ... }

@Delete("/{id}")
@ResponseStatus(204)
fun delete(@PathVariable id: String) { }  // Unit return → no body
```

`@ResponseStatus` sets the default status code for successful responses. The framework uses the annotation's value when the controller returns normally. The value can still be overridden by returning an explicit `Response` or `PingConn`.

---

### Content Negotiation

Content negotiation is handled by a middleware in the pipeline. The `ContentNegotiation` middleware reads `Accept` and `Content-Type` headers and configures serializers in `conn.private`:

```kotlin
pipeline(.api) {
    plug(ContentNegotiation) {
        json()              // application/json via KorE's built-in serializer
        xml(XmlSerializer)  // application/xml via custom serializer
    }
    plug(AuthMiddleware)
}
```

Controller return types are serialized using the negotiated format. If no acceptable format is available, the middleware returns 406.

---

### Async Controller Actions

On the BEAM, async is not what it means in other environments. A `Task` in Ping is a process-based future. Returning a `Task` from a controller means the request process spawns a child process for the computation and waits for its result — which is still synchronous from the HTTP client's perspective.

```kotlin
@Get("/{id}")
fun show(@PathVariable id: String): Task<UserResponse> {
    return Task {
        // Runs in a separate process, linked to the request process
        userService.findById(id)
            .map { UserResponse.from(it) }
            .orThrow { NotFoundException(it) }
    }
}
```

The more interesting async case is parallel fetching:

```kotlin
@Get("/{id}/dashboard")
fun dashboard(@PathVariable id: String): DashboardResponse {
    // All three run concurrently in separate processes
    val (user, posts, notifications) = Task.awaitAll(
        Task { userService.findById(id).orThrow() },
        Task { postService.recentByUser(id) },
        Task { notificationService.unreadFor(id) }
    )
    return DashboardResponse(user, posts, notifications)
}
```

This is genuinely better than Spring's async model. Spring requires `@Async`, a thread pool executor, and `CompletableFuture` chaining. Ping uses `Task` which is a lightweight process — spawning three concurrent processes costs ~6KB of heap and the scheduler handles preemption. No thread pool to tune.

---

### The BEAM Process Advantage

In Spring, each request consumes a thread from a pool (typically 200 threads by default). Under load, thread pool exhaustion causes request queuing. Thread stacks are 512KB–1MB each. The 200-thread default is a deliberate resource constraint.

In Ping, each request is a BEAM process with a 2KB initial heap. The scheduler multiplexes tens of thousands of processes across available CPU cores. There is no pool to exhaust (within memory limits). A system handling 10,000 concurrent connections in Ping uses ~20MB for process overhead; the same in Spring requires ~200MB for thread stacks alone, assuming the thread pool is sized appropriately.

Ping's documentation should present this prominently. This is not marketing — it is a structural consequence of the BEAM's process model. Spring developers who have tuned thread pool sizes, fought queue overflow, and debugged thread starvation will find this immediately compelling.

---

### Complete CRUD Controller Example

```kotlin
// user_controller.kore
@RestController
class UserController(private val userService: UserService) {

    @Get
    fun index(
        @RequestParam(defaultValue = "1") page: Int,
        @RequestParam(defaultValue = "20") pageSize: Int,
        @RequestParam(required = false) search: String?
    ): PagedResponse<UserResponse> {
        return userService.list(
            page = page,
            pageSize = pageSize,
            search = search
        ) |> PagedResponse.from(_, UserResponse::from)
    }

    @Get("/{id}")
    fun show(@PathVariable id: String): UserResponse {
        return when (val result = userService.findById(id)) {
            is Ok -> UserResponse.from(result.value)
            is Err -> throw NotFoundException("User not found: $id")
        }
    }

    @Post
    @ResponseStatus(201)
    fun create(@Valid @RequestBody request: CreateUserRequest): UserResponse {
        return when (val result = userService.create(request)) {
            is Ok -> UserResponse.from(result.value)
            is Err -> throw when (result.error) {
                is DuplicateEmailError -> ConflictException("Email already registered")
                is ValidationError -> UnprocessableEntityException(result.error.violations)
                else -> InternalException(result.error)
            }
        }
    }

    @Put("/{id}")
    fun update(
        @PathVariable id: String,
        @Valid @RequestBody request: UpdateUserRequest
    ): UserResponse {
        return when (val result = userService.update(id, request)) {
            is Ok -> UserResponse.from(result.value)
            is Err -> throw when (result.error) {
                is NotFoundError -> NotFoundException("User not found: $id")
                is ValidationError -> UnprocessableEntityException(result.error.violations)
                else -> InternalException(result.error)
            }
        }
    }

    @Delete("/{id}")
    @ResponseStatus(204)
    fun delete(@PathVariable id: String) {
        when (val result = userService.delete(id)) {
            is Ok -> Unit
            is Err -> throw NotFoundException("User not found: $id")
        }
    }
}

// DTOs
data class CreateUserRequest(
    @NotBlank val email: String,
    @NotBlank @Size(min = 8) val password: String,
    @NotBlank val name: String
)

data class UpdateUserRequest(
    val name: String?,
    val email: String?
)

data class UserResponse(
    val id: String,
    val email: String,
    val name: String,
    val createdAt: Long
) {
    companion object {
        fun from(user: User): UserResponse =
            UserResponse(
                id = user.id,
                email = user.email,
                name = user.name,
                createdAt = user.createdAt
            )
    }
}
```

---

## 10.5 — Dependency Injection on the BEAM

### Why Spring DI Exists

Spring's DI container exists to solve a specific problem: in a multi-threaded JVM application, you want shared service objects to be initialized once, be available to any component that needs them, and have their lifecycle managed by the container. Threads share memory, so a singleton service is literally one object in the heap, accessible from any thread. The DI container is an object graph manager.

The problem it solves is real. Manual wiring of large object graphs is tedious and error-prone. Swapping implementations for testing requires either runtime configuration or constructor argument plumbing throughout the call stack.

### Why the BEAM Doesn't Need the Same Solution

On the BEAM, processes do not share memory. A "singleton service" cannot be a single object in a shared heap — there is no shared heap. Instead, a shared stateful service is a named process (a `GenServer`) that owns its state in its own process heap. Clients interact with it via message passing.

Stateless services — modules that perform computations but hold no state — are just modules. A module is a BEAM code unit loaded once into the code server. Calling a module function is always available without any container.

The consequence: BEAM applications don't need a DI container for the same reason they don't need thread synchronization. The problem the container solves is a JVM-specific problem. On the BEAM, the OTP supervision tree and process model solve the same underlying problem in a structurally different way.

Ping must be honest about this. Spring developers understand DI as "how I get my dependencies." On the BEAM, you get your dependencies by calling a named process or calling a module function. Ping provides Spring-familiar annotation syntax for both, but what it generates is different from what Spring generates.

---

### The Three-Tier System

Ping's DI model has three tiers:

**Tier 1: Stateless Module Functions — `@Component`**

For services that have no state — pure functions, utility logic, formatters, validators — there is no process. The module is compiled, loaded into the BEAM, and its functions are called directly. No initialization. No supervision.

```kotlin
@Component
class EmailFormatter {
    fun formatWelcome(user: User): EmailMessage =
        EmailMessage(
            to = user.email,
            subject = "Welcome to the platform",
            body = templates.welcome(user)
        )
}
```

**What it compiles to:** A plain BEAM module `'KorE.EmailFormatter'`. The `@Component` annotation tells the DI resolver to make it available for injection, but at runtime it is just a module function call.

**Tier 2: Stateful Named GenServer — `@Service`/`@Singleton`**

For services that own state — caches, connection pools, session stores, counters — the service is a named `GenServer` started under the application supervisor.

```kotlin
@Service
class SessionService(private val store: SessionStore) {
    private val sessions = mutableMapOf<String, Session>()

    fun create(userId: String): Session {
        val session = Session.new(userId)
        sessions[session.id] = session
        return session
    }

    fun find(sessionId: String): Session? =
        sessions[sessionId]

    fun invalidate(sessionId: String) {
        sessions.remove(sessionId)
    }
}
```

**What it compiles to:**

```kotlin
// Generated by compiler
@BEAMModule("KorE.SessionService")
class SessionServiceServer : GenServer<SessionServiceState, SessionServiceCall, Unit>() {
    override fun init(args: Dynamic): Ok<SessionServiceState> =
        Ok(SessionServiceState(
            store = args.narrow<SessionStore>(),
            sessions = emptyMap()
        ))

    override fun handleCall(
        msg: SessionServiceCall,
        from: From,
        state: SessionServiceState
    ): Reply<Any?, SessionServiceState> = when (msg) {
        is Create -> {
            val session = Session.new(msg.userId)
            reply(session, state.copy(sessions = state.sessions + (session.id to session)))
        }
        is Find -> reply(state.sessions[msg.sessionId], state)
        is Invalidate -> reply(Unit, state.copy(sessions = state.sessions - msg.sessionId))
    }
}
```

The `@Service` compiler transform is substantial. It rewrites the class body into a `GenServer` with call types for each public method. The state structure is inferred from the class's mutable fields. Public methods become `handleCall` clauses. This transform happens in the annotation processing phase of compilation.

Injectors receive a process handle, not the object. Calling `sessionService.create(userId)` compiles to `GenServer.call(:'KorE.SessionService', {:create, userId})`.

**Tier 3: Repository — `@Repository`**

Repositories are `@Service` with additional query/command semantics and integration with Ping's database access layer (analogous to Ecto's Repo). They compile to named GenServers with a connection pool under their own supervisor.

```kotlin
@Repository
class UserRepository(private val db: Database) {

    fun findById(id: String): Ok<User> | Err<NotFoundError> =
        db.query(User, "SELECT * FROM users WHERE id = $1", id)
            .mapEmpty { NotFoundError("User $id") }

    fun findByEmail(email: String): User? =
        db.queryOne(User, "SELECT * FROM users WHERE email = $1", email)

    fun save(user: User): Ok<User> | Err<DatabaseError> =
        db.insert(user)

    fun update(user: User): Ok<User> | Err<DatabaseError> =
        db.update(user)

    fun delete(id: String): Ok<Unit> | Err<DatabaseError> =
        db.delete(User, id)
}
```

**What it compiles to:** A `GenServer` wrapping a database connection pool. The repository's `db` parameter resolves to a connection pool process. Each method call acquires a connection from the pool, executes the query, and releases the connection. The GenServer is the pool manager; queries are dispatched to pool worker processes.

---

### `@Autowired` and Constructor Injection

Ping supports both constructor injection (preferred) and field injection (`@Autowired`).

**Constructor injection (preferred):**

```kotlin
@RestController
class UserController(
    private val userService: UserService,
    private val cacheService: CacheService,
    private val auditService: AuditService
)
```

The constructor parameters are resolved by type at application start. For Tier 1 (`@Component`) dependencies, the compiler inlines the module reference. For Tier 2/3 (`@Service`/`@Repository`) dependencies, the compiler generates a process registration lookup. The resolved dependencies are stored in `conn.private.services` and made available to the controller factory.

**Field injection (`@Autowired`):**

```kotlin
@RestController
class UserController {
    @Autowired private lateinit var userService: UserService
}
```

Field injection is supported for compatibility but is not recommended. In Ping, the "object" being injected into is a module, not a bean — there is no object instantiation at request time. Field injection compiles to a module attribute lookup. The `lateinit` modifier is meaningless at the BEAM level (modules are loaded, not instantiated), but is accepted syntactically.

---

### The Generated Supervision Tree

`@PingApplication` generates a supervision tree that includes all registered services:

```
PingApplication.Supervisor (strategy: :oneForOne)
├── Ping.Endpoint.Supervisor (strategy: :oneForAll)
│   ├── Ping.Acceptor (TCP connection acceptor)
│   └── Ping.ConnectionPool (per-request process pool)
├── PingApp.ServiceRegistry.Supervisor (strategy: :oneForOne)
│   ├── UserRepository (GenServer)
│   ├── SessionService (GenServer)
│   ├── CacheService (GenServer)
│   └── AuditService (GenServer)
└── PingApp.Database.Supervisor (strategy: :restForOne)
    ├── Database.ConnectionPool
    └── Database.QueryMonitor
```

The tree is generated from the set of `@Service`, `@Repository`, and `@Singleton` annotations found during compilation. The developer does not write this tree manually. But it is visible — the compiler emits `generated/supervision_tree.kore` showing the full tree structure. Developers can inspect it, and can override it by writing a `supervision_tree.kore` file manually.

---

### Testing: Mock Injection

Testing stateless `@Component` classes is trivial — they are modules with no state.

Testing `@Service` classes (which compile to GenServers) requires replacing the named process. Ping provides a `MockRegistry` for tests:

```kotlin
// Test setup
@PingTest
class UserControllerTest {

    @MockService
    private val userService: UserService = mockOf {
        on { findById("user-1") } returns Ok(testUser)
        on { findById("user-99") } returns Err(NotFoundError("user-99"))
    }

    @Test
    fun `returns 200 with user for valid id`() {
        val response = get("/api/v1/users/user-1")
        assert(response.status == 200)
        assert(response.body<UserResponse>().id == "user-1")
    }

    @Test
    fun `returns 404 for unknown user`() {
        val response = get("/api/v1/users/user-99")
        assert(response.status == 404)
    }
}
```

`@MockService` replaces the named GenServer with a test double for the duration of the test. The replacement is per-process — the test process's service registry is isolated from the global one. This is possible because BEAM process dictionaries are per-process. A test can register a mock under the service name in its own process scope without affecting other tests running concurrently.

---

### Complete Example: UserService with UserRepository

```kotlin
// user_repository.kore
@Repository
class UserRepository(private val db: Database) {

    fun findById(id: String): Ok<User> | Err<NotFoundError> =
        db.query(User, "SELECT * FROM users WHERE id = $1", id)
            .mapEmpty { NotFoundError("User not found: $id") }

    fun findByEmail(email: String): Ok<User> | Err<NotFoundError> =
        db.queryOne(User, "SELECT * FROM users WHERE email = $1", email)
            .mapEmpty { NotFoundError("No user with email: $email") }

    fun save(user: User): Ok<User> | Err<DatabaseError> =
        db.insert(User::class, user)

    fun update(user: User): Ok<User> | Err<DatabaseError> =
        db.update(User::class, user)

    fun delete(id: String): Ok<Unit> | Err<DatabaseError> =
        db.delete(User::class, id)
}

// user_service.kore
@Service
class UserService(
    private val userRepository: UserRepository,
    private val passwordHasher: PasswordHasher,
    private val eventBus: EventBus
) {
    fun findById(id: String): Ok<User> | Err<NotFoundError> =
        userRepository.findById(id)

    fun create(request: CreateUserRequest): Ok<User> | Err<CreateUserError> {
        return when (val existing = userRepository.findByEmail(request.email)) {
            is Ok -> Err(DuplicateEmailError(request.email))
            is Err -> {
                val hashedPassword = passwordHasher.hash(request.password)
                val user = User.new(
                    email = request.email,
                    passwordHash = hashedPassword,
                    name = request.name
                )
                when (val saved = userRepository.save(user)) {
                    is Ok -> {
                        eventBus.publish(UserCreatedEvent(saved.value))
                        Ok(saved.value)
                    }
                    is Err -> Err(DatabaseError(saved.error))
                }
            }
        }
    }

    fun update(id: String, request: UpdateUserRequest): Ok<User> | Err<UpdateUserError> {
        return when (val found = userRepository.findById(id)) {
            is Err -> Err(NotFoundError(id))
            is Ok -> {
                val updated = found.value.copy(
                    name = request.name ?: found.value.name,
                    email = request.email ?: found.value.email
                )
                when (val saved = userRepository.update(updated)) {
                    is Ok -> Ok(saved.value)
                    is Err -> Err(DatabaseError(saved.error))
                }
            }
        }
    }

    fun delete(id: String): Ok<Unit> | Err<NotFoundError> {
        return when (userRepository.findById(id)) {
            is Err -> Err(NotFoundError(id))
            is Ok -> {
                userRepository.delete(id)
                    .mapErr { NotFoundError(id) }
            }
        }
    }

    fun list(page: Int, pageSize: Int, search: String?): PagedResult<User> =
        userRepository.list(page, pageSize, search)
}

// user_controller.kore (using the service)
@RestController
class UserController(private val userService: UserService) {

    @Get("/{id}")
    fun show(@PathVariable id: String): UserResponse {
        return when (val result = userService.findById(id)) {
            is Ok -> UserResponse.from(result.value)
            is Err -> throw NotFoundException(result.error.message)
        }
    }

    @Post
    @ResponseStatus(201)
    fun create(@Valid @RequestBody request: CreateUserRequest): UserResponse {
        return when (val result = userService.create(request)) {
            is Ok -> UserResponse.from(result.value)
            is Err -> throw result.error.toPingException()
        }
    }
}
```

---

## 10.6 — Exception Handling and Error Responses

### The Core Tension

Spring's exception handling model is built on the assumption that exceptions are the primary error propagation mechanism. `@ExceptionHandler` methods catch exceptions thrown anywhere in the call stack below the dispatcher. `@ControllerAdvice` provides global exception handling across all controllers. The model works well — exceptions propagate through the call stack automatically, and the handler intercepts them at a centralized point.

BEAM's model is different. Exceptions in Erlang/Elixir are genuine unexpected failures (what Erlang calls `error` class throws), not control flow. Expected failure paths use tuples (`{error, reason}`) or, in KorE, `Err<T>`. "Let it crash" means that when something genuinely unexpected happens, you do not try to recover — you let the process crash and trust the supervisor to restart it.

Ping resolves this tension by separating concerns:

- **Domain errors** (`Ok`/`Err`) are modeled with types. Controllers handle them explicitly.
- **HTTP exception classes** (`NotFoundException`, `UnauthorizedException`, etc.) are thrown for known HTTP semantics and caught by Ping's exception handler middleware.
- **Unexpected crashes** are genuine process crashes. The endpoint supervisor catches them and returns 500. No application code handles them — that is the supervisor's job.

---

### `@ExceptionHandler` in KorE

```kotlin
@RestController
class UserController(private val userService: UserService) {

    @ExceptionHandler(NotFoundException::class)
    fun handleNotFound(e: NotFoundException): ProblemDetail =
        ProblemDetail.notFound(e.message)

    @ExceptionHandler(ValidationException::class)
    fun handleValidation(e: ValidationException): ProblemDetail =
        ProblemDetail.unprocessableEntity(e.violations)

    @Get("/{id}")
    fun show(@PathVariable id: String): UserResponse {
        return when (val result = userService.findById(id)) {
            is Ok -> UserResponse.from(result.value)
            is Err -> throw NotFoundException("User $id not found")
        }
    }
}
```

Controller-local `@ExceptionHandler` methods handle exceptions thrown within that controller's handlers. They take precedence over global handlers.

---

### `@ControllerAdvice` — Global Exception Handlers

```kotlin
@ControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(NotFoundException::class)
    @ResponseStatus(404)
    fun handleNotFound(e: NotFoundException): ProblemDetail =
        ProblemDetail(
            type = "https://errors.example.com/not-found",
            title = "Resource Not Found",
            status = 404,
            detail = e.message,
            instance = e.resourcePath
        )

    @ExceptionHandler(UnauthorizedException::class)
    @ResponseStatus(401)
    fun handleUnauthorized(e: UnauthorizedException): ProblemDetail =
        ProblemDetail(
            type = "https://errors.example.com/unauthorized",
            title = "Unauthorized",
            status = 401,
            detail = "Authentication required"
        )

    @ExceptionHandler(ConflictException::class)
    @ResponseStatus(409)
    fun handleConflict(e: ConflictException): ProblemDetail =
        ProblemDetail(
            type = "https://errors.example.com/conflict",
            title = "Conflict",
            status = 409,
            detail = e.message
        )

    @ExceptionHandler(ValidationException::class)
    @ResponseStatus(422)
    fun handleValidation(e: ValidationException): ValidationProblemDetail =
        ValidationProblemDetail(
            type = "https://errors.example.com/validation-error",
            title = "Validation Failed",
            status = 422,
            violations = e.violations
        )

    // Catch-all for unexpected errors
    // This handler runs ONLY if the request process has not crashed —
    // i.e., the error was thrown via Exception, not a BEAM crash
    @ExceptionHandler(Exception::class)
    @ResponseStatus(500)
    fun handleUnexpected(e: Exception): ProblemDetail {
        Logger.error("Unhandled exception in request process", e)
        return ProblemDetail(
            type = "https://errors.example.com/internal-error",
            title = "Internal Server Error",
            status = 500,
            detail = "An unexpected error occurred"
        )
    }
}
```

`@ControllerAdvice` compiles to a middleware installed at the end of the exception handling chain. It wraps the entire handler pipeline in a try/catch. Exceptions thrown by controller code propagate up to this wrapper.

**The critical distinction:** `@ControllerAdvice` handles KorE/JVM-style exceptions thrown with `throw`. It does not handle BEAM-level crashes (e.g., a `badmatch` error, a failed pattern match on a nil). BEAM-level crashes kill the request process. The endpoint supervisor catches the process exit signal, logs it, and sends a 500. This is correct behavior — a BEAM crash indicates a programmer error or corrupted state, not a domain error.

---

### ProblemDetail / RFC 9457

Ping uses RFC 9457 ProblemDetail as the standard error response format:

```kotlin
data class ProblemDetail(
    val type: String = "about:blank",
    val title: String,
    val status: Int,
    val detail: String? = null,
    val instance: String? = null,
    val extensions: Map<String, Any?> = emptyMap()
) {
    companion object {
        fun notFound(detail: String?) = ProblemDetail("about:blank", "Not Found", 404, detail)
        fun unauthorized() = ProblemDetail("about:blank", "Unauthorized", 401)
        fun badRequest(detail: String?) = ProblemDetail("about:blank", "Bad Request", 400, detail)
        fun unprocessableEntity(violations: List<Violation>) =
            ValidationProblemDetail(title = "Validation Failed", status = 422, violations = violations)
    }
}

data class ValidationProblemDetail(
    override val type: String = "about:blank",
    override val title: String,
    override val status: Int,
    override val detail: String? = null,
    override val instance: String? = null,
    val violations: List<Violation>
) : ProblemDetail(type, title, status, detail, instance)

data class Violation(
    val field: String,
    val message: String,
    val rejectedValue: Any? = null
)
```

JSON output for a validation error:

```json
{
  "type": "https://errors.example.com/validation-error",
  "title": "Validation Failed",
  "status": 422,
  "violations": [
    { "field": "email", "message": "must not be blank" },
    { "field": "password", "message": "size must be between 8 and 100" }
  ]
}
```

---

### Mapping `Ok`/`Err` to HTTP Responses

The recommended pattern is to throw HTTP exception classes at the controller boundary rather than propagating `Err` types up through Ping's middleware. This keeps domain errors in the domain layer and HTTP semantics at the HTTP layer:

```kotlin
// Domain layer — returns typed errors
fun findById(id: String): Ok<User> | Err<NotFoundError>

// Controller — translates domain errors to HTTP exceptions
@Get("/{id}")
fun show(@PathVariable id: String): UserResponse {
    return when (val result = userService.findById(id)) {
        is Ok -> UserResponse.from(result.value)
        is Err -> throw NotFoundException(result.error.message)
    }
}

// Global handler translates HTTP exceptions to ProblemDetail
@ExceptionHandler(NotFoundException::class)
@ResponseStatus(404)
fun handleNotFound(e: NotFoundException): ProblemDetail = ProblemDetail.notFound(e.message)
```

Alternatively, Ping provides an `ErrorMapper` DSL for declarative mapping:

```kotlin
@ControllerAdvice
class GlobalExceptionHandler {

    val errorMapper = errorMapper {
        map<NotFoundException> { e -> ProblemDetail.notFound(e.message) } withStatus 404
        map<ConflictException> { e -> ProblemDetail("about:blank", "Conflict", 409, e.message) } withStatus 409
        map<ValidationException> { e ->
            ValidationProblemDetail(title = "Validation Failed", status = 422, violations = e.violations)
        } withStatus 422
        map<UnauthorizedException> { _ -> ProblemDetail.unauthorized() } withStatus 401
        map<Exception> { e ->
            Logger.error("Unhandled", e)
            ProblemDetail("about:blank", "Internal Server Error", 500)
        } withStatus 500
    }
}
```

---

## 10.7 — Validation

### Annotation-Based Validation

Ping supports JSR-380 (Bean Validation)-compatible annotations. These are familiar to Spring developers and map directly to what they already know:

```kotlin
data class CreateUserRequest(
    @field:NotBlank(message = "Email is required")
    @field:Email(message = "Must be a valid email address")
    val email: String,

    @field:NotBlank(message = "Password is required")
    @field:Size(min = 8, max = 100, message = "Password must be 8-100 characters")
    val password: String,

    @field:NotBlank(message = "Name is required")
    @field:Size(min = 1, max = 255)
    val name: String,

    @field:Min(0)
    @field:Max(150)
    val age: Int? = null,

    @field:Pattern(
        regexp = "[A-Z]{2}",
        message = "Must be a 2-letter country code"
    )
    val countryCode: String? = null
)
```

The `@field:` prefix (required in KorE/Kotlin) indicates the annotation targets the property field rather than the constructor parameter. Without `@field:`, the annotation targets the constructor parameter, which has no effect on validation.

**Available validation annotations:**

| Annotation | Description | BEAM implementation |
|---|---|---|
| `@NotNull` | Value must not be null | Pattern match on `nil` |
| `@NotBlank` | String must not be blank | `:string.trim/1` check |
| `@Size(min, max)` | String/collection length | `:erlang.byte_size/1` or `length/1` |
| `@Min(value)` | Minimum numeric value | Guard comparison |
| `@Max(value)` | Maximum numeric value | Guard comparison |
| `@Email` | Must be valid email | Regex match |
| `@Pattern(regexp)` | Must match regex | `:re.run/2` |
| `@Positive` | Must be > 0 | Guard comparison |
| `@PositiveOrZero` | Must be ≥ 0 | Guard comparison |
| `@Past` | Date must be in past | Timestamp comparison |
| `@Future` | Date must be in future | Timestamp comparison |

---

### How Validation Integrates with PingConn

Validation runs as a middleware stage, after body parsing and before the controller is called. The `ValidationMiddleware` is automatically installed when `@Valid` is present on a `@RequestBody` parameter:

```kotlin
// The middleware chain for a validated endpoint:
// 1. JsonParser — parses body, puts in conn.body
// 2. ParameterBinder — binds @RequestBody to CreateUserRequest
// 3. ValidationMiddleware — validates bound object, collects violations
// 4. Controller function — only called if validation passes

@Post
fun create(@Valid @RequestBody request: CreateUserRequest): UserResponse { ... }
```

If validation fails, `ValidationMiddleware` halts the pipeline and returns a 422 response with a `ValidationProblemDetail` body. The controller is never called.

The compiler generates a validator function for each validated data class:

```kotlin
// Generated by compiler for CreateUserRequest
fun validate(request: CreateUserRequest): List<Violation> = buildList {
    if (request.email.isBlank())
        add(Violation("email", "Email is required"))
    if (!request.email.matches(EMAIL_REGEX))
        add(Violation("email", "Must be a valid email address"))
    if (request.password.isBlank())
        add(Violation("password", "Password is required"))
    if (request.password.length < 8 || request.password.length > 100)
        add(Violation("password", "Password must be 8-100 characters"))
    if (request.name.isBlank())
        add(Violation("name", "Name is required"))
    request.age?.let { age ->
        if (age < 0) add(Violation("age", "must be greater than or equal to 0"))
        if (age > 150) add(Violation("age", "must be less than or equal to 150"))
    }
    request.countryCode?.let { code ->
        if (!code.matches(Regex("[A-Z]{2}")))
            add(Violation("countryCode", "Must be a 2-letter country code"))
    }
}
```

All violations are collected before returning — no fail-fast behavior. The entire list of violations is returned so the client can correct all errors in one round trip.

---

### Custom Validators

```kotlin
// Define the annotation
@Target(AnnotationTarget.FIELD)
@Retention(AnnotationRetention.RUNTIME)
@Constraint(validatedBy = [UniqueEmailValidator::class])
annotation class UniqueEmail(
    val message: String = "Email address is already registered"
)

// Implement the validator
class UniqueEmailValidator(
    private val userRepository: UserRepository
) : ConstraintValidator<UniqueEmail, String> {
    override fun isValid(value: String?, context: ConstraintValidatorContext): Boolean {
        if (value == null) return true  // @NotNull handles nulls
        return when (userRepository.findByEmail(value)) {
            is Ok -> false  // found = not unique
            is Err -> true  // not found = unique
        }
    }
}

// Usage
data class CreateUserRequest(
    @field:NotBlank
    @field:Email
    @field:UniqueEmail
    val email: String,
    // ...
)
```

Custom validators that need dependencies (like `UniqueEmailValidator` needing `UserRepository`) are resolved through Ping's DI system. The `@Constraint(validatedBy = ...)` annotation tells the compiler to inject an instance of the validator class, which in turn resolves its dependencies through the normal DI chain.

---

### Type-Level Validation (Refined Types)

For cases where validation is a core invariant of the type rather than a request-level check, Ping supports refined types:

```kotlin
// Refined type — construction validates at the point of creation
@Refined
value class Email(val value: String) {
    init {
        require(value.isNotBlank()) { "Email must not be blank" }
        require(value.matches(EMAIL_REGEX)) { "Invalid email format: $value" }
    }
}

@Refined
value class PasswordHash private constructor(val hash: String) {
    companion object {
        fun of(plaintext: String): Ok<PasswordHash> | Err<ValidationError> {
            if (plaintext.length < 8) return Err(ValidationError("Password too short"))
            return Ok(PasswordHash(BCrypt.hash(plaintext)))
        }
    }
}

// Usage — the type system enforces validity
data class User(
    val id: String,
    val email: Email,  // Can never hold an invalid email
    val passwordHash: PasswordHash
)
```

Refined types are the right tool for domain invariants. `@field:Email` annotations are the right tool for request DTO validation. They solve different problems and should not be conflated.

---

## 10.8 — WebSocket and Channels

### The Channel Model

Ping's WebSocket support is built on Phoenix Channels semantics: connections join topics, and events flow bidirectionally within those topics. This is a richer model than bare WebSocket, and it maps naturally to the BEAM's process model.

Each WebSocket connection is a dedicated BEAM process — a `Channel` process that is a specialized GenServer. When a client connects, a channel process is spawned and linked to the endpoint supervisor. The channel process handles join/leave/event messages from the client and can send messages back to the client or broadcast to all subscribers of a topic.

This is structurally excellent for the BEAM. Tens of thousands of concurrent WebSocket connections means tens of thousands of channel processes. Each is isolated — a misbehaving connection crashes its own process without affecting any other connection.

---

### `@WebSocketController`

```kotlin
@WebSocketController(topic = "notification:{userId}")
class NotificationChannel(
    private val notificationService: NotificationService,
    private val presence: Presence
) {

    @OnConnect
    fun onJoin(
        socket: ChannelSocket,
        params: Map<String, String>
    ): Ok<ChannelState> | Err<String> {
        val userId = socket.assigns["userId"] as? String
            ?: return Err("Unauthorized")

        // Track presence
        presence.track(socket, userId, mapOf(
            "online_at" to BEAMTime.now(),
            "device" to params["device"]
        ))

        // Send initial state
        socket.push("initial_state", mapOf(
            "unreadCount" to notificationService.unreadCount(userId)
        ))

        return Ok(ChannelState(userId = userId))
    }

    @OnDisconnect
    fun onLeave(
        socket: ChannelSocket,
        reason: LeaveReason,
        state: ChannelState
    ) {
        Logger.info("User ${state.userId} left notification channel")
        // Presence cleanup is automatic when the process exits
    }

    @OnMessage("mark_read")
    fun onMarkRead(
        socket: ChannelSocket,
        payload: MarkReadPayload,
        state: ChannelState
    ): Ok<ChannelState> | Err<String> {
        return when (notificationService.markRead(state.userId, payload.notificationId)) {
            is Ok -> {
                socket.push("notification_read", mapOf("id" to payload.notificationId))
                Ok(state)
            }
            is Err -> Err("Failed to mark notification as read")
        }
    }

    @OnMessage("mark_all_read")
    fun onMarkAllRead(
        socket: ChannelSocket,
        payload: EmptyPayload,
        state: ChannelState
    ): Ok<ChannelState> | Err<String> {
        notificationService.markAllRead(state.userId)
        socket.push("all_notifications_read", emptyMap())
        return Ok(state)
    }
}
```

**The `topic` parameter** supports pattern matching: `"notification:{userId}"` means this channel handles any topic matching that pattern. The `{userId}` segment is extracted and available in `socket.topic_params["userId"]`.

**What the compiler generates:** Each `@WebSocketController` class compiles to a module implementing the `Channel` behaviour (analogous to Phoenix's `Phoenix.Channel`). The `@OnConnect` method becomes `join/3`, `@OnDisconnect` becomes `terminate/2`, and `@OnMessage(event)` methods become `handle_in/3` clauses pattern-matched on the event name.

---

### Broadcasting

```kotlin
// From within a channel handler
socket.broadcast("new_notification", notificationPayload)
// Sends to all sockets currently subscribed to the same topic

// From outside a channel (e.g., from a service when a new notification arrives)
@Service
class NotificationService(private val channelBroadcaster: ChannelBroadcaster) {

    fun createAndNotify(userId: String, notification: Notification) {
        val saved = notificationRepository.save(notification)
        // Broadcast to all of this user's connected clients
        channelBroadcaster.broadcast(
            topic = "notification:$userId",
            event = "new_notification",
            payload = NotificationPayload.from(saved)
        )
    }
}
```

Broadcasting to a topic sends the message to the `PubSub` process associated with that topic. All channel processes subscribed to the topic receive the message and forward it to their connected clients. This uses BEAM's `pg` (process groups) module under the hood — the same mechanism Phoenix PubSub uses.

---

### Phoenix.Presence Integration

```kotlin
@WebSocketController(topic = "room:{roomId}")
class ChatChannel(private val presence: Presence) {

    @OnConnect
    fun onJoin(socket: ChannelSocket, params: Map<String, String>): Ok<ChannelState> | Err<String> {
        val user = socket.assigns["currentUser"] as? User
            ?: return Err("Unauthorized")

        // Track this connection in presence
        presence.track(socket, user.id, mapOf(
            "name" to user.name,
            "joinedAt" to BEAMTime.now()
        ))

        // Push current presence state to joining client
        socket.push("presence_state", presence.list(socket.topic))

        return Ok(ChannelState(roomId = socket.topicParams["roomId"]!!, userId = user.id))
    }

    // Presence diffs are automatically pushed to all subscribers
    // when any client joins or leaves. No explicit handler needed.
}
```

Ping's `Presence` module wraps `Phoenix.Presence` directly. The BEAM-level implementation is unchanged — only the API surface is KorE-idiomatic. Presence tracks which users are connected to which topics, handles CRDT-based conflict resolution for distributed systems, and automatically broadcasts join/leave diffs to all subscribers.

---

### Complete Example: Real-Time Notification Channel

```kotlin
// notification_channel.kore
data class ChannelState(
    val userId: String,
    val roomId: String? = null
)

data class MarkReadPayload(val notificationId: String)
data class NotificationPayload(
    val id: String,
    val type: String,
    val title: String,
    val body: String,
    val createdAt: Long
) {
    companion object {
        fun from(n: Notification): NotificationPayload =
            NotificationPayload(n.id, n.type, n.title, n.body, n.createdAt)
    }
}

@WebSocketController(topic = "notification:{userId}")
class NotificationChannel(
    private val notificationService: NotificationService,
    private val presence: Presence
) {

    @OnConnect
    fun onJoin(
        socket: ChannelSocket,
        params: Map<String, String>
    ): Ok<ChannelState> | Err<String> {
        val currentUser = socket.assigns["currentUser"] as? User
            ?: return Err("Unauthorized: missing authentication")

        val topicUserId = socket.topicParams["userId"]
            ?: return Err("Invalid topic")

        // Users can only subscribe to their own notification topic
        if (currentUser.id != topicUserId) {
            return Err("Unauthorized: cannot subscribe to another user's notifications")
        }

        presence.track(socket, currentUser.id, mapOf(
            "status" to "online",
            "connectedAt" to BEAMTime.now()
        ))

        val unread = notificationService.findUnread(currentUser.id)
        socket.push("initial_notifications", mapOf("notifications" to unread.map(NotificationPayload::from)))

        return Ok(ChannelState(userId = currentUser.id))
    }

    @OnDisconnect
    fun onLeave(socket: ChannelSocket, reason: LeaveReason, state: ChannelState) {
        Logger.info("Notification channel disconnected for user ${state.userId}: $reason")
    }

    @OnMessage("mark_read")
    fun onMarkRead(
        socket: ChannelSocket,
        payload: MarkReadPayload,
        state: ChannelState
    ): Ok<ChannelState> | Err<String> {
        return when (notificationService.markRead(state.userId, payload.notificationId)) {
            is Ok -> {
                socket.reply(.ok, mapOf("id" to payload.notificationId))
                Ok(state)
            }
            is Err -> Err("Notification not found or already read")
        }
    }

    @OnMessage("mark_all_read")
    fun onMarkAllRead(
        socket: ChannelSocket,
        payload: Map<String, Any?>,
        state: ChannelState
    ): Ok<ChannelState> | Err<String> {
        notificationService.markAllRead(state.userId)
        socket.reply(.ok, mapOf("cleared" to true))
        return Ok(state)
    }
}
```

The WebSocket transport upgrade happens in the endpoint pipeline before the channel router dispatches to `NotificationChannel`. The channel router matches topics using the same pattern-matching router as the HTTP router, generating efficient BEAM function clauses.

---

## 10.9 — Security

### Authentication Pipeline

Security in Ping is not a magic container context — it is middleware that enriches `PingConn.assigns`. There is no `SecurityContextHolder.getContext().getAuthentication()` global. There is `conn.assigns["currentUser"]`. The difference matters: per-request isolation is structural, not conventional.

The authentication flow:

1. `AuthMiddleware` reads the `Authorization` header
2. It verifies the JWT and extracts claims
3. It calls `userService.findById(claims.subject)` to load the user
4. It sets `conn.assigns["currentUser"] = user`
5. Downstream controllers access `conn.currentUser`

If authentication fails, `AuthMiddleware` halts the pipeline and returns 401. Unauthenticated controllers never run.

---

### JWT Authentication Built-In

```kotlin
// config/application.kore.yml
ping:
  security:
    jwt:
      secret: ${JWT_SECRET}
      expiry: 3600   # seconds
      issuer: "my-app"
      algorithm: HS256

// auth_middleware.kore
class AuthMiddleware(
    private val jwtService: JwtService,
    private val userRepository: UserRepository
) : Middleware {

    override fun call(conn: PingConn): PingConn {
        val token = extractToken(conn) ?: return conn  // unauthenticated, pass through

        return when (val claims = jwtService.verify(token)) {
            is Err -> conn
                .putStatus(401)
                .json(ProblemDetail("about:blank", "Invalid Token", 401, claims.error.message))
                .halt()
            is Ok -> when (val user = userRepository.findById(claims.value.subject)) {
                is Err -> conn
                    .putStatus(401)
                    .json(ProblemDetail("about:blank", "User Not Found", 401))
                    .halt()
                is Ok -> conn.assign("currentUser", user.value)
            }
        }
    }

    private fun extractToken(conn: PingConn): String? =
        conn.headers.get("Authorization")
            ?.takeIf { it.startsWith("Bearer ") }
            ?.removePrefix("Bearer ")
}

// jwt_service.kore
@Service
class JwtService(private val config: JwtConfig) {

    fun sign(userId: String, roles: List<String>): String =
        JWT.create()
            .withSubject(userId)
            .withClaim("roles", roles)
            .withIssuer(config.issuer)
            .withExpiresAt(BEAMTime.now() + config.expiry.seconds)
            .sign(Algorithm.HMAC256(config.secret))

    fun verify(token: String): Ok<JwtClaims> | Err<JwtError> =
        runCatching {
            val decoded = JWT.require(Algorithm.HMAC256(config.secret))
                .withIssuer(config.issuer)
                .build()
                .verify(token)
            Ok(JwtClaims(
                subject = decoded.subject,
                roles = decoded.getClaim("roles").asList(String::class.java)
            ))
        }.getOrElse { e -> Err(JwtError(e.message ?: "Token verification failed")) }
}
```

---

### Role-Based Authorization DSL

```kotlin
// Role-based route protection in the router
router {
    pipeline(.api) {
        plug(JsonParser)
        plug(AuthMiddleware)
    }

    pipeline(.admin_api) {
        pipe_through(.api)
        plug(RequireRole(.admin))
    }

    scope("/api/v1") {
        pipe_through(.api)
        resources("/users", UserController)
        resources("/posts", PostController)

        scope("/admin") {
            pipe_through(.admin_api)
            resources("/users", AdminUserController)
            resources("/settings", AdminSettingsController)
        }
    }
}

// require_role.kore
class RequireRole(private val requiredRole: Atom) : Middleware {
    override fun call(conn: PingConn): PingConn {
        val user = conn.currentUser
            ?: return conn
                .putStatus(401)
                .json(ProblemDetail.unauthorized())
                .halt()

        if (!user.hasRole(requiredRole.name)) {
            return conn
                .putStatus(403)
                .json(ProblemDetail("about:blank", "Forbidden", 403,
                    "Role '${requiredRole.name}' required"))
                .halt()
        }

        return conn
    }
}
```

For method-level authorization, Ping provides `@Secured` and `@PreAuthorize`:

```kotlin
@RestController
class AdminUserController(private val userService: UserService) {

    @Get
    @Secured("admin")
    fun index(): List<UserResponse> { ... }

    @Delete("/{id}")
    @PreAuthorize("hasRole('admin') or #id == currentUser.id")
    fun delete(@PathVariable id: String) { ... }
}
```

`@Secured` compiles to a middleware added to the specific handler's pipeline. `@PreAuthorize` with SpEL-like expressions compiles to a guard function that receives `conn.assigns` as context. The expression `#id == currentUser.id` compiles to a comparison between the path variable `id` and `conn.currentUser.id`.

---

### Per-Process SecurityContext

There is no `SecurityContextHolder`. There is `conn.currentUser`. This is not a downgrade — it is structurally superior.

In Spring, `SecurityContextHolder` uses thread-local storage. If you spawn a new thread (for async processing, scheduled tasks, etc.), you must manually transfer the security context to the new thread. This is a common source of bugs — `getAuthentication()` returns null in async code because the security context was not copied.

In Ping, the `currentUser` is in `conn.assigns`. The `conn` is passed explicitly through the pipeline. There is no ambient context to forget to copy. If you spawn a `Task` inside a controller and need the current user, you capture it from `conn` explicitly:

```kotlin
@Get("/{id}/export")
fun export(@PathVariable id: String): Response {
    val user = conn.currentUser ?: throw UnauthorizedException()

    // Explicitly pass user to the async task — no ambient context
    val task = Task {
        exportService.generateReport(id, requestedBy = user.id)
    }

    return Response.accepted(mapOf("taskId" to task.id))
}
```

The explicitness is a feature. Security-relevant context (who is making this request) is always visible in the code, never hidden in a thread-local.

---

## 10.10 — Observability and Actuator

### Auto-Generated Endpoints

`@PingApplication` automatically registers an actuator-equivalent at `/ping/`:

```
GET /ping/health      — health check (aggregates all health indicators)
GET /ping/metrics     — Prometheus-compatible metrics
GET /ping/info        — application info (version, config subset)
GET /ping/processes   — BEAM process count, memory
GET /ping/supervisor  — supervision tree status
```

These endpoints are served by a separate lightweight endpoint on a different port (default: 4001) to prevent actuator traffic from affecting application traffic and to allow network-level firewall rules to restrict actuator access.

---

### BEAM Telemetry Integration

Spring Actuator pulls metrics from MBeans, Micrometer registries, and custom actuator endpoints. Ping uses `:telemetry` — the BEAM-native structured event system — as its metrics backbone. `:telemetry` is the standard for Phoenix, Ecto, and the broader BEAM ecosystem. Every significant operation emits a telemetry event.

```kotlin
// Ping automatically emits these telemetry events:
// [:ping, :request, :start]  — when request processing begins
// [:ping, :request, :stop]   — when request processing ends
// [:ping, :request, :exception] — when request process crashes

// Attaching a custom telemetry handler
@Component
class RequestMetricsCollector {

    @PostConstruct
    fun attach() {
        Telemetry.attach(
            "request-metrics",
            listOf(listOf(.ping, .request, .stop))
        ) { eventName, measurements, metadata, _ ->
            Metrics.histogram(
                "ping.request.duration",
                measurements["duration"] as Long,
                Tags.of(
                    "method" to (metadata["conn"] as PingConn).method.name,
                    "status" to (metadata["conn"] as PingConn).status.toString(),
                    "route" to (metadata["route"] as String)
                )
            )
        }
    }
}
```

Built-in metrics (auto-collected):
- `ping.request.duration` — histogram, tagged by method/status/route
- `ping.request.count` — counter, tagged by method/status
- `beam.process.count` — gauge, from `:erlang.system_info(:process_count)`
- `beam.memory.total` — gauge, from `:erlang.memory(:total)`
- `beam.memory.processes` — gauge
- `beam.run_queue` — gauge, scheduler run queue length
- `beam.gc.count` — counter, GC events
- `db.query.duration` — histogram, tagged by repo/query

---

### Custom Health Indicators

```kotlin
// Implement HealthIndicator
@Component
class DatabaseHealthIndicator(
    private val userRepository: UserRepository
) : HealthIndicator {

    override fun health(): Health {
        return when (userRepository.ping()) {
            is Ok -> Health.up()
                .withDetail("database", "PostgreSQL")
                .withDetail("responseTime", "${measureMs { userRepository.ping() }}ms")
                .build()
            is Err -> Health.down()
                .withDetail("error", "Database unreachable")
                .build()
        }
    }
}

@Component
class ExternalApiHealthIndicator(
    private val httpClient: HttpClient
) : HealthIndicator {

    override fun health(): Health {
        return try {
            val response = httpClient.get("https://api.example.com/health")
            if (response.status == 200) Health.up().build()
            else Health.degraded()
                .withDetail("status", response.status)
                .build()
        } catch (e: Exception) {
            Health.down()
                .withException(e)
                .build()
        }
    }
}
```

Health indicators are aggregated at `/ping/health`:

```json
{
  "status": "UP",
  "components": {
    "database": {
      "status": "UP",
      "details": {
        "database": "PostgreSQL",
        "responseTime": "2ms"
      }
    },
    "externalApi": {
      "status": "UP"
    },
    "diskSpace": {
      "status": "UP",
      "details": {
        "total": 107374182400,
        "free": 53687091200,
        "threshold": 10485760
      }
    }
  }
}
```

If any component reports `DOWN`, the aggregate status is `DOWN` and the endpoint returns HTTP 503. If any component reports `DEGRADED`, the aggregate status is `DEGRADED` and the endpoint returns HTTP 207.

---

### BEAM Observer and `:recon` Integration

Ping integrates with the BEAM's built-in observability tools:

```kotlin
// Enable Observer web UI (Phoenix LiveDashboard equivalent)
@PingApplication(
    observability = Observability(
        observer = true,         // Enable :observer web interface
        recon = true,            // Enable :recon_web interface
        dashboard = true         // Enable Ping Live Dashboard at /ping/dashboard
    )
)
class MyApp
```

The Ping Live Dashboard provides real-time visualization of:
- Request throughput and latency percentiles
- BEAM process count and memory usage
- Supervisor tree health
- Recent errors with stack traces
- Database query performance

This is equivalent to Spring Boot Admin + Spring Actuator + a profiler, built on BEAM's native tooling (`:observer`, `:recon`, `:telemetry`).

---

## 10.11 — The Ping Application: Startup and Supervision

### `@PingApplication`

```kotlin
// main.kore
@PingApplication(
    port = 4000,
    environment = Environment.DEV,
    config = "config/application.kore.yml"
)
fun main() {
    Ping.start()
}
```

`@PingApplication` is the single entry point annotation. It triggers the generation of the full OTP application, supervision tree, and all required infrastructure. The `main()` function body is minimal — `Ping.start()` hands off to the generated OTP application.

---

### Generated OTP Application

The compiler generates an OTP application module:

```kotlin
// Generated: 'KorE.MyApp.Application'
@BEAMModule("KorE.MyApp.Application")
class MyAppApplication : OTPApplication() {

    override fun start(type: StartType, args: List<Dynamic>): Ok<Pid> | Err<Dynamic> {
        val children = listOf(
            childSpec(MyApp.Supervisor, strategy = .oneForOne)
        )
        return Supervisor.startLink(children, strategy = .oneForOne)
    }
}
```

The root supervisor is `MyApp.Supervisor`, also generated. Its children are assembled from:
1. The Ping endpoint infrastructure (acceptors, connection pool)
2. All `@Service` and `@Repository` components found during compilation
3. The database connection pool (if a database is configured)
4. The channel socket server (if `@WebSocketController`s are present)
5. The PubSub server (if broadcasting is used)

---

### The Full Generated Supervision Tree

```
MyApp.Supervisor (strategy: :oneForOne)
│
├── Ping.Endpoint.Supervisor (strategy: :oneForAll)
│   │   (oneForAll: if acceptor dies, restart connection pool too)
│   ├── Ping.Cowboy.Acceptor (HTTP/1.1 + HTTP/2 acceptor, port 4000)
│   ├── Ping.ConnectionPool (DynamicSupervisor for request processes)
│   └── Ping.ChannelServer (WebSocket channel router, if applicable)
│
├── MyApp.Services.Supervisor (strategy: :oneForOne)
│   │   (oneForOne: service failures are isolated)
│   ├── UserRepository (GenServer, name: :KorE_UserRepository)
│   ├── SessionService (GenServer, name: :KorE_SessionService)
│   ├── CacheService (GenServer, name: :KorE_CacheService)
│   └── AuditService (GenServer, name: :KorE_AuditService)
│
├── MyApp.Database.Supervisor (strategy: :restForOne)
│   │   (restForOne: pool monitor must restart after pool restarts)
│   ├── Database.ConnectionPool (postgrex pool)
│   └── Database.QueryMonitor (telemetry monitor)
│
├── Ping.PubSub (Phoenix.PubSub, for channel broadcasting)
├── Ping.Presence (Phoenix.Presence, if presence is used)
│
└── Ping.Actuator.Endpoint (HTTP endpoint on port 4001 for /ping/*)
```

The supervisor tree is deterministic and compiler-generated. The developer can inspect it in `generated/supervision_tree.kore`, which is always up to date with the current set of annotations in the codebase.

To override the generated tree (e.g., to add a custom supervisor, change restart strategies), create `supervision_tree.kore` at the project root:

```kotlin
// supervision_tree.kore — override generated tree
@PingSupervisionTree
fun supervisionTree(): SupervisorSpec = supervisor {
    strategy(.oneForOne)

    // Use the generated endpoint supervisor as-is
    child(Ping.Endpoint.Supervisor)

    // Custom supervisor for our services
    child(supervisor("services") {
        strategy(.oneForOne)
        child(UserRepository)
        child(UserService)
        child(EmailService)
    })

    // Add a custom worker
    child(MyApp.BackgroundJobWorker, restart = .permanent)

    // Database with custom pool size
    child(Database.ConnectionPool, poolSize = 20)
}
```

---

### Configuration

**`config/application.kore.yml`** is the Spring-familiar configuration format:

```yaml
# config/application.kore.yml
ping:
  port: 4000
  secret_key_base: ${SECRET_KEY_BASE}

  security:
    jwt:
      secret: ${JWT_SECRET}
      expiry: 3600
      issuer: "my-app"

database:
  url: ${DATABASE_URL}
  pool_size: 10

logging:
  level: info
  format: json  # or "text" for development

---
# config/application-dev.kore.yml (dev profile overrides)
ping:
  port: 4000

database:
  url: "postgres://localhost/myapp_dev"
  pool_size: 5

logging:
  level: debug
  format: text
```

Profile activation:

```bash
PING_ENV=dev ./myapp
PING_ENV=prod ./myapp
```

Or at compile time:

```kotlin
@PingApplication(environment = Environment.PROD)
fun main() { Ping.start() }
```

The environment profile system compiles to `Mix.env()` / `Application.get_env/2` under the hood. `application.kore.yml` compiles to `config/config.exs` and environment-specific overrides compile to `config/{env}.exs`. The YAML format is the developer-facing surface; the Erlang config system is what runs.

---

### Hot Code Reload

BEAM supports hot code reload — updating running code without restarting the system. This is more sophisticated than Spring Boot DevTools' class reloading.

In development mode, Ping monitors source files and recompiles changed modules. Changed modules are loaded into the running system via BEAM's code server. Running processes that are in the middle of a call to the old module complete with the old code; new calls use the new code. This is safe — BEAM's code server keeps two versions of a module in memory simultaneously during upgrades.

```kotlin
// config/application-dev.kore.yml
ping:
  hot_reload:
    enabled: true
    watch_paths:
      - "src/"
      - "lib/"
    ignore_paths:
      - "src/test/"
```

For production hot upgrades, Ping supports OTP release upgrades via `appup` files — the same mechanism used by Erlang/OTP systems that have been running continuously for years. This is beyond the scope of most web frameworks. It is a BEAM feature, and Ping exposes it.

---

### Complete Application Entry Point

```kotlin
// main.kore — complete application entry point

@PingApplication(
    port = 4000,
    config = "config/application.kore.yml"
)
fun main() {
    Logger.info("Starting MyApp on port 4000")
    Logger.info("Environment: ${Ping.environment()}")
    Logger.info("BEAM version: ${BEAMInfo.oTPVersion()}")
    Ping.start()
}

// The compiler generates this from the above + all annotations found:
//
// MyApp.Supervisor (oneForOne)
// ├── Ping.Endpoint (port 4000)
// │   ├── HTTP Acceptor
// │   ├── ConnectionPool (DynamicSupervisor)
// │   └── ChannelServer
// ├── MyApp.Services (oneForOne)
// │   ├── UserRepository
// │   ├── SessionService
// │   ├── CacheService
// │   └── AuditService
// ├── Database.Supervisor (restForOne)
// │   ├── PostgreSQL.ConnectionPool (size: 10)
// │   └── Database.QueryMonitor
// ├── Ping.PubSub
// └── Ping.Actuator (port 4001)

// config/application.kore.yml (development)
// ping:
//   port: 4000
//   hot_reload:
//     enabled: true
//   security:
//     jwt:
//       secret: dev-secret-not-for-production
//       expiry: 86400
//
// database:
//   url: "postgres://localhost/myapp_dev"
//   pool_size: 5
//
// logging:
//   level: debug
//   format: text
```

---

## 10.12 — Language Feature Requirements Inventory

This section is a precise inventory of what Ping requires from the KorE compiler and language. Each item states what it is, what it must generate, and which compiler phase handles it.

---

### 1. Annotation Processing Model

**What it is:** Annotations like `@RestController`, `@GetMapping`, `@Service`, `@Autowired` must be processed at compile time to generate BEAM modules, routing tables, and supervision tree entries.

**What it must generate:**
- `@RestController` → BEAM module with one exported function per `@Get`/`@Post`/etc. annotated method
- `@Service` → GenServer module with `init/1`, `handle_call/3`, `handle_cast/2`, `terminate/2`; registration in service supervisor child spec
- `@Repository` → GenServer wrapping a connection pool; child spec in database supervisor
- `@Component` → Plain BEAM module; registration in DI resolver table for injection
- `@WebSocketController` → Channel behaviour module with `join/3`, `handle_in/3`, `terminate/2`
- `@PingApplication` → OTP application module, full supervision tree, mix.exs/rebar.config

**Compiler phase:** Annotation processing runs as a dedicated pass between parsing and type checking. Annotations that transform class structure (e.g., `@Service` which rewrites instance fields to GenServer state) must run before type checking so that the type checker sees the transformed structure.

**Implementation note:** Annotation processors in KorE are macro-like compiler plugins registered in `kore.toml`. The compiler provides a `CompilerContext` API that annotation processors use to read annotated elements, query types, and emit new module definitions. Annotation processors cannot modify existing source — they emit new generated files to `generated/`.

---

### 2. Route Compilation

**What it is:** The router DSL (`router { scope("/api") { get("/users/{id}", ...) } }`) must be evaluated at compile time to produce a routing module.

**What it must generate:**

A BEAM module `'KorE.MyApp.Router'` with pattern-matched function clauses:

```erlang
% Generated Erlang
route(Conn = #{method := <<"GET">>, path_segments := [<<"api">>, <<"v1">>, <<"users">>, Id]}) ->
    Conn2 = maps:put(path_params, #{<<"id">> => Id}, Conn),
    pipeline([log, json_parser, auth], Conn2,
             fun(C) -> 'KorE.UserController':show(C) end);
route(Conn = #{method := <<"POST">>, path_segments := [<<"api">>, <<"v1">>, <<"users">>]}) ->
    pipeline([log, json_parser, auth], Conn,
             fun(C) -> 'KorE.UserController':create(C) end);
```

The routing trie is compiled to a decision tree of pattern matches. The compiler uses a trie-building algorithm (similar to Phoenix's Router) to minimize the number of comparisons on the hot path.

**Compiler phase:** Route compilation is a compile-time evaluation pass. The router DSL is evaluated as a KorE program at compile time, producing a `RouteTable` data structure. The `RouteTable` is then code-generated into the `'KorE.Router'` Erlang module.

**Conflict detection:** The compiler validates the route table for conflicts (two routes matching the same method + path) and emits `KE2001: Duplicate route` as a compile error.

---

### 3. Parameter Binding

**What it is:** `@PathVariable`, `@RequestParam`, `@RequestBody`, `@RequestHeader` annotations on controller method parameters must be compiled to extraction code that reads from `PingConn`.

**What it must generate:**

For a method `fun show(@PathVariable id: String, @RequestParam page: Int?)`:

```kotlin
// Generated binding code (conceptual KorE)
fun show_binding(conn: PingConn): PingConn {
    val id: String = conn.pathParams["id"]
        ?: return conn.putStatus(400)
            .json(ProblemDetail.badRequest("Missing path variable: id"))
            .halt()

    val page: Int? = conn.queryParams["page"]
        ?.firstOrNull()
        ?.toIntOrNull()

    return UserController.show(conn, id, page)
}
```

For `@RequestBody request: CreateUserRequest`:

```kotlin
val request: CreateUserRequest = when (val body = conn.body) {
    is Body.Parsed<*> -> body.value as? CreateUserRequest
        ?: return conn.putStatus(400).json(ProblemDetail.badRequest("Body type mismatch")).halt()
    else -> return conn.putStatus(400).json(ProblemDetail.badRequest("Body not parsed")).halt()
}
```

**Compiler phase:** Parameter binding code generation is part of the controller compilation pass. Each annotated controller method is wrapped in a generated binding function. The binding function is what the router calls; the binding function calls the controller method after extracting and coercing parameters.

**Type coercion table:**

| Target type | Coercion | Failure behavior |
|-------------|----------|-----------------|
| `String` | Identity | Never fails |
| `Int` | `toIntOrNull()` | 400 if null |
| `Long` | `toLongOrNull()` | 400 if null |
| `Double` | `toDoubleOrNull()` | 400 if null |
| `Boolean` | `toBooleanStrictOrNull()` | 400 if null |
| `UUID` | `UUID.fromString()` | 400 if throws |
| `T?` | Nullable — coerce if present, null if absent | Never fails |

---

### 4. Middleware Pipeline Composition

**What it is:** Pipeline declarations (`pipeline(.api) { plug(A); plug(B) }`) must be compiled to efficient pipeline execution code.

**What it must generate:**

Two strategies are available:

**Strategy A: Runtime list** — Store middleware as a list, fold at request time.

```kotlin
val apiPipeline: List<Middleware> = listOf(
    RequestLogger.instance,
    JsonParser.instance,
    AuthMiddleware.instance
)

fun runPipeline(conn: PingConn): PingConn =
    apiPipeline.fold(conn) { c, mw -> if (c.halted) c else mw.call(c) }
```

**Strategy B: Compile-time inlining** — Small, known pipelines can be inlined:

```kotlin
// Compiler generates this from pipeline(.api) { plug(A); plug(B); plug(C) }
fun runApiPipeline(conn: PingConn): PingConn {
    val c1 = if (conn.halted) conn else A.call(conn)
    val c2 = if (c1.halted) c1 else B.call(c1)
    val c3 = if (c2.halted) c2 else C.call(c2)
    return c3
}
```

Strategy B avoids the list allocation and fold overhead on the hot path. The compiler should choose Strategy B for pipelines with ≤8 middlewares (configurable), falling back to Strategy A for longer pipelines.

**Compiler phase:** Pipeline composition is resolved at route compilation time, when the full set of middlewares for each route is known. Pipelines are inlined into the generated routing function.

---

### 5. DI Resolution

**What it is:** Constructor parameters and `@Autowired` fields annotated on `@RestController`, `@Service`, `@Component`, and `@Repository` classes must be resolved at application startup.

**What it must generate:**

A `ServiceRegistry` module that maps type names to instances:

```kotlin
// Generated: 'KorE.MyApp.ServiceRegistry'
object ServiceRegistry {
    val userRepository: UserRepository by lazy {
        GenServer.call(:'KorE.UserRepository', .get_instance) as UserRepository
    }
    val userService: UserService by lazy {
        // UserService depends on UserRepository and EventBus
        GenServer.call(:'KorE.UserService', .get_instance) as UserService
    }
    val userController: UserController by lazy {
        UserController(userService)  // stateless, no GenServer
    }
}
```

The DI graph is computed at compile time. Circular dependencies are detected during annotation processing and reported as `KE4001: Circular dependency: UserService → UserRepository → UserService`.

**Compiler phase:** DI graph resolution is an annotation processing pass. The compiler builds a directed graph of dependencies from constructor parameters and `@Autowired` annotations. Topological sort determines initialization order. The `ServiceRegistry` is generated with dependencies initialized in the correct order.

---

### 6. Serialization

**What it is:** Controller return values (data classes, lists, primitive types) must be serialized to JSON (or other negotiated format) without explicit serializer calls.

**What it must generate:**

For each `data class` used as a controller return type, the compiler generates a serializer module:

```kotlin
// Generated for UserResponse data class
object UserResponseSerializer {
    fun toJson(value: UserResponse): ByteArray =
        buildJsonObject {
            put("id", value.id)
            put("email", value.email)
            put("name", value.name)
            put("createdAt", value.createdAt)
        }.toByteArray()

    fun fromJson(bytes: ByteArray): Ok<UserResponse> | Err<DeserializationError> =
        runCatching {
            val obj = parseJsonObject(bytes)
            Ok(UserResponse(
                id = obj.getString("id"),
                email = obj.getString("email"),
                name = obj.getString("name"),
                createdAt = obj.getLong("createdAt")
            ))
        }.getOrElse { e -> Err(DeserializationError(e.message)) }
}
```

Serializers are generated at compile time. No reflection. No runtime introspection. The serializer module is called by the controller wrapper generated in the parameter binding phase.

**Null handling:** Null fields in data classes serialize as JSON `null`. Use `T?` types to allow null fields; non-nullable fields that are null at serialization time throw a compile-detected warning (the type system should prevent this, but defensive runtime checks are generated for `Dynamic` interop paths).

**Custom serialization:** Annotate the class with `@JsonProperty`, `@JsonIgnore`, `@JsonSerialize(using = ...)` for customization.

**Compiler phase:** Serializer generation is an annotation processing pass that runs after type resolution, so all types of all fields are known. Serializers are emitted to `generated/serializers/`.

---

### 7. Validation Annotation Processing

**What it is:** `@NotBlank`, `@Size`, `@Email`, `@Min`, `@Max`, `@Pattern` annotations on `data class` fields must generate validation functions.

**What it must generate:**

For each `data class` with `@field:*` validation annotations, the compiler generates:

```kotlin
// Generated for CreateUserRequest
object CreateUserRequestValidator {
    fun validate(value: CreateUserRequest): List<Violation> = buildList {
        if (value.email.isBlank())
            add(Violation("email", "must not be blank"))
        if (!value.email.matches(EMAIL_REGEX))
            add(Violation("email", "must be a well-formed email address"))
        if (value.password.isBlank())
            add(Violation("password", "must not be blank"))
        if (value.password.length < 8 || value.password.length > 100)
            add(Violation("password", "size must be between 8 and 100"))
        // ... etc.
    }
}
```

The generated validator is a pure function — no reflection, no annotation inspection at runtime. Validation is compile-time code generation.

**Custom validators:** Custom `@Constraint` annotations require a `ConstraintValidator` implementation. The compiler generates a call to the validator's `isValid()` method in the generated validation function. If the `ConstraintValidator` has injected dependencies, its constructor is resolved via the DI system.

**Compiler phase:** Validation code generation is an annotation processing pass running after type resolution.

---

### 8. WebSocket Channel Code Generation

**What it is:** `@WebSocketController` annotated classes with `@OnConnect`, `@OnDisconnect`, `@OnMessage` annotated methods must be compiled to Phoenix Channel behaviour modules.

**What it must generate:**

```erlang
% Generated from @WebSocketController(topic = "notification:{userId}")
-module('KorE.NotificationChannel').
-behaviour('Elixir.Phoenix.Channel').
-export([join/3, handle_in/3, handle_out/3, terminate/2]).

join(<<"notification:", UserId/binary>>, Params, Socket) ->
    %% Calls KorE-generated onJoin wrapper
    'KorE.NotificationChannel.Impl':on_join(Socket, Params, UserId);
join(_, _, _Socket) ->
    {error, #{reason => <<"invalid_topic">>}}.

handle_in(<<"mark_read">>, Payload, Socket) ->
    'KorE.NotificationChannel.Impl':on_mark_read(Socket, Payload);
handle_in(<<"mark_all_read">>, Payload, Socket) ->
    'KorE.NotificationChannel.Impl':on_mark_all_read(Socket, Payload);
handle_in(Event, _Payload, Socket) ->
    {reply, {error, #{reason => <<"unknown_event">>, event => Event}}, Socket}.

terminate(Reason, Socket) ->
    'KorE.NotificationChannel.Impl':on_leave(Socket, Reason).
```

The `Impl` module contains the KorE-compiled versions of the annotated methods.

**Compiler phase:** Channel code generation is an annotation processing pass.

---

### 9. PingConn and Its BEAM Representation

**What it is:** `PingConn` must be an efficient, immutable carrier type that is passed through all middleware and controller code.

**BEAM representation:** `PingConn` compiles to an Erlang map with atom keys. The decision to use a map (rather than a record) is deliberate:

- Maps are structurally shareable — `conn.copy(status = 200)` is a map update that shares unmodified keys
- Maps support the open `assigns` field without type-level generics
- Map pattern matching in BEAM is efficient for small maps (< ~32 keys) using hash array mapped tries

The fixed keys of `PingConn` are known at compile time:

```erlang
% PingConn BEAM representation
#{
    method     => <<"GET">>,
    path       => <<"/api/v1/users/123">>,
    path_params => #{<<"id">> => <<"123">>},
    query_params => #{},
    headers    => #{<<"content-type">> => <<"application/json">>},
    body       => unread,
    status     => 200,
    resp_headers => #{},
    resp_body  => <<>>,
    halted     => false,
    assigns    => #{},
    private    => #{},
    adapter    => {cowboy_adapter, ...}
}
```

`PingConn.copy()` compiles to a map update expression, which in BEAM generates a `maps:update/3` call or, for known keys, a more efficient map literal with updated fields.

**Compiler phase:** `PingConn` is a compiler-known type. The compiler generates optimized map access and update code for `PingConn` field access and `copy()` calls.

---

### 10. What the Ping Runtime Library Provides vs. What the Compiler Generates

This boundary is important for understanding what is a language feature and what is a library:

**Compiler generates (compile-time):**
- Router module with pattern-matched route clauses
- Controller binding functions (parameter extraction, coercion, validation dispatch)
- Serializer modules for all data classes used as controller return types
- Validator modules for all data classes with validation annotations
- GenServer modules for `@Service`/`@Repository` annotated classes
- Channel behaviour modules for `@WebSocketController` annotated classes
- Supervision tree specification module
- OTP application module
- `ServiceRegistry` module with resolved DI graph
- `Routes` object with URL generation functions
- `generated/supervision_tree.kore` documentation file

**Ping runtime library provides (pre-compiled BEAM modules shipped with Ping):**
- `Ping.Endpoint` — cowboy-based HTTP/2 + WebSocket endpoint
- `Ping.Router.run/2` — pipeline execution (Strategy A fallback)
- `Ping.PingConn` — the `PingConn` module with helper functions (`halt/1`, `putStatus/2`, `json/2`, `assign/3`, etc.)
- `Ping.JwtService` — JWT signing and verification (wraps `:joken` or `:jose`)
- `Ping.ContentNegotiation` — content negotiation middleware
- `Ping.JsonParser` — body parsing middleware (wraps `:jason`)
- `Ping.Presence` — Phoenix.Presence wrapper with KorE API
- `Ping.ChannelBroadcaster` — topic broadcast interface
- `Ping.Actuator` — health endpoint infrastructure
- `Ping.Telemetry` — telemetry attachment and metrics collection
- `Ping.TestClient` — HTTP test client for integration tests

The boundary is: if it requires knowledge of your application's specific classes, routes, or types, the compiler generates it. If it is generic infrastructure that works for any Ping application, it is in the runtime library.

This boundary has a compiler tooling implication: the Ping runtime library is an ordinary KorE/Erlang dependency in `kore.toml`. It does not require any special compiler support. The compiler-generated code depends on the runtime library — not the other way around.