defmodule Kore.AST do
  @moduledoc """
  AST node structs for the KorE compiler.

  Every node carries `meta: %{line: integer(), col: integer()}` for diagnostics.
  """

  # ── File-level nodes ─────────────────────────────────────────────────

  defmodule File do
    @moduledoc "Root node: imports + module declaration."
    defstruct [:imports, :module, :meta]
    @type t :: %__MODULE__{imports: [Kore.AST.Import.t()], module: Kore.AST.Module.t(), meta: map()}
  end

  defmodule Import do
    @moduledoc "`import elixir.X.Y` — dotted path."
    defstruct [:path, :meta]
    @type t :: %__MODULE__{path: [String.t()], meta: map()}
  end

  defmodule Module do
    @moduledoc "Top-level `module Name { declarations }`."
    defstruct [:name, :declarations, :meta]
    @type t :: %__MODULE__{name: String.t(), declarations: [term()], meta: map()}
  end

  # ── Declarations ─────────────────────────────────────────────────────

  defmodule FunDecl do
    @moduledoc "Function declaration."
    defstruct [:name, :params, :return_type, :body, :meta]
    @type t :: %__MODULE__{
            name: String.t(),
            params: [Kore.AST.Param.t()],
            return_type: term() | nil,
            body: term(),
            meta: map()
          }
  end

  defmodule Param do
    @moduledoc "Function parameter: `name: Type = default`."
    defstruct [:name, :type, :default, :meta]
    @type t :: %__MODULE__{name: String.t(), type: term(), default: term() | nil, meta: map()}
  end

  defmodule DataDecl do
    @moduledoc "`data Name(val field: Type, ...)` — record/struct."
    defstruct [:name, :fields, :meta]
    @type t :: %__MODULE__{name: String.t(), fields: [Kore.AST.DataField.t()], meta: map()}
  end

  defmodule DataField do
    @moduledoc "Field in a data declaration: `val name: Type = default`."
    defstruct [:name, :type, :default, :meta]
    @type t :: %__MODULE__{name: String.t(), type: term(), default: term() | nil, meta: map()}
  end

  defmodule SealedDecl do
    @moduledoc "`sealed Name { data Variant(...) ... }` — sum type."
    defstruct [:name, :variants, :meta]
    @type t :: %__MODULE__{name: String.t(), variants: [Kore.AST.DataDecl.t()], meta: map()}
  end

  defmodule ActorDecl do
    @moduledoc "`actor Name(fields) { methods }` — GenServer."
    defstruct [:name, :fields, :methods, :meta]
    @type t :: %__MODULE__{
            name: String.t(),
            fields: [Kore.AST.ActorField.t()],
            methods: [Kore.AST.FunDecl.t()],
            meta: map()
          }
  end

  defmodule ActorField do
    @moduledoc "Actor state field: `val|var name: Type = default`."
    defstruct [:name, :type, :default, :mutable, :meta]
    @type t :: %__MODULE__{
            name: String.t(),
            type: term(),
            default: term() | nil,
            mutable: boolean(),
            meta: map()
          }
  end

  defmodule ValDecl do
    @moduledoc "`val x = expr` or `var x = expr`."
    defstruct [:name, :type, :value, :mutable, :meta]
    @type t :: %__MODULE__{
            name: String.t(),
            type: term() | nil,
            value: term(),
            mutable: boolean(),
            meta: map()
          }
  end

  # ── Statements ───────────────────────────────────────────────────────

  defmodule Assign do
    @moduledoc "Variable reassignment: `name = expr`."
    defstruct [:name, :value, :meta]
    @type t :: %__MODULE__{name: String.t(), value: term(), meta: map()}
  end

  defmodule Return do
    @moduledoc "`return expr` — only valid in tail position for MVP."
    defstruct [:value, :meta]
    @type t :: %__MODULE__{value: term() | nil, meta: map()}
  end

  defmodule Block do
    @moduledoc "`{ statement; ... }` — sequence of statements."
    defstruct [:statements, :meta]
    @type t :: %__MODULE__{statements: [term()], meta: map()}
  end

  # ── Expressions ──────────────────────────────────────────────────────

  defmodule If do
    @moduledoc "`if (cond) then else` — expression."
    defstruct [:condition, :then_branch, :else_branch, :meta]
    @type t :: %__MODULE__{condition: term(), then_branch: term(), else_branch: term() | nil, meta: map()}
  end

  defmodule When do
    @moduledoc "`when (subject) { branches }` — pattern matching."
    defstruct [:subject, :branches, :meta]
    @type t :: %__MODULE__{subject: term(), branches: [Kore.AST.WhenBranch.t()], meta: map()}
  end

  defmodule WhenBranch do
    @moduledoc "A single branch in a `when` expression."
    defstruct [:pattern, :body, :meta]
    @type t :: %__MODULE__{pattern: term(), body: term(), meta: map()}
  end

  defmodule PatternIs do
    @moduledoc "`is TypeName(val a, val b)` — destructuring pattern."
    defstruct [:type_name, :bindings, :meta]
    @type t :: %__MODULE__{type_name: String.t(), bindings: [String.t()] | nil, meta: map()}
  end

  defmodule PatternValue do
    @moduledoc "Value pattern: `1, 2, 3` — matches any of the values."
    defstruct [:values, :meta]
    @type t :: %__MODULE__{values: [term()], meta: map()}
  end

  defmodule PatternElse do
    @moduledoc "`else` — wildcard/default branch."
    defstruct [:meta]
    @type t :: %__MODULE__{meta: map()}
  end

  defmodule Lambda do
    @moduledoc "`{ params -> body }` or `{ body }` (implicit `it`)."
    defstruct [:params, :body, :meta]
    @type t :: %__MODULE__{params: [String.t()] | nil, body: [term()], meta: map()}
  end

  defmodule Call do
    @moduledoc "Function call: `name(args)` or `ModuleName.func(args)`."
    defstruct [:function, :args, :trailing_lambda, :meta]
    @type t :: %__MODULE__{function: term(), args: [term()], trailing_lambda: term() | nil, meta: map()}
  end

  defmodule MethodCall do
    @moduledoc "Method call: `receiver.method(args)`."
    defstruct [:receiver, :method, :args, :trailing_lambda, :meta]
    @type t :: %__MODULE__{
            receiver: term(),
            method: String.t(),
            args: [term()],
            trailing_lambda: term() | nil,
            meta: map()
          }
  end

  defmodule FieldAccess do
    @moduledoc "`receiver.field` — dot access."
    defstruct [:receiver, :field, :meta]
    @type t :: %__MODULE__{receiver: term(), field: String.t(), meta: map()}
  end

  defmodule SafeAccess do
    @moduledoc "`receiver?.field` — null-safe access."
    defstruct [:receiver, :field, :meta]
    @type t :: %__MODULE__{receiver: term(), field: String.t(), meta: map()}
  end

  defmodule Elvis do
    @moduledoc "`left ?: right` — elvis/null-coalescing operator."
    defstruct [:left, :right, :meta]
    @type t :: %__MODULE__{left: term(), right: term(), meta: map()}
  end

  defmodule NotNull do
    @moduledoc "`expr!!` — force unwrap (raises on nil)."
    defstruct [:expr, :meta]
    @type t :: %__MODULE__{expr: term(), meta: map()}
  end

  defmodule BinOp do
    @moduledoc "Binary operation: `left op right`."
    defstruct [:op, :left, :right, :meta]
    @type t :: %__MODULE__{op: atom(), left: term(), right: term(), meta: map()}
  end

  defmodule UnaryOp do
    @moduledoc "Unary operation: `-x` or `!x`."
    defstruct [:op, :operand, :meta]
    @type t :: %__MODULE__{op: atom(), operand: term(), meta: map()}
  end

  defmodule Literal do
    @moduledoc "Literal value: int, double, string, bool, null, atom."
    defstruct [:type, :value, :meta]
    @type t :: %__MODULE__{type: atom(), value: term(), meta: map()}
  end

  defmodule StringInterp do
    @moduledoc "Interpolated string: parts are `{:string, text}` or `{:expr, ast}`."
    defstruct [:parts, :meta]
    @type t :: %__MODULE__{parts: [term()], meta: map()}
  end

  defmodule VarRef do
    @moduledoc "Variable reference."
    defstruct [:name, :meta]
    @type t :: %__MODULE__{name: String.t(), meta: map()}
  end

  defmodule ConstructorCall do
    @moduledoc "`TypeName(args)` — data/sealed constructor."
    defstruct [:type_name, :args, :meta]
    @type t :: %__MODULE__{type_name: String.t(), args: [term()], meta: map()}
  end

  defmodule CopyCall do
    @moduledoc "`expr.copy(field = value, ...)` — struct update."
    defstruct [:receiver, :updates, :meta]
    @type t :: %__MODULE__{receiver: term(), updates: [{String.t(), term()}], meta: map()}
  end

  defmodule Spawn do
    @moduledoc "`spawn { body }` — spawn a process."
    defstruct [:body, :meta]
    @type t :: %__MODULE__{body: term(), meta: map()}
  end

  defmodule Receive do
    @moduledoc "`receive { branches }` — receive message."
    defstruct [:branches, :meta]
    @type t :: %__MODULE__{branches: [Kore.AST.WhenBranch.t()], meta: map()}
  end

  defmodule For do
    @moduledoc "`for (x in iterable) { body }`."
    defstruct [:var, :iterable, :body, :meta]
    @type t :: %__MODULE__{var: String.t(), iterable: term(), body: term(), meta: map()}
  end

  defmodule Range do
    @moduledoc "`from..to` — range expression."
    defstruct [:from, :to, :meta]
    @type t :: %__MODULE__{from: term(), to: term(), meta: map()}
  end

  defmodule ListLit do
    @moduledoc "`listOf(a, b, c)` — list literal."
    defstruct [:elements, :meta]
    @type t :: %__MODULE__{elements: [term()], meta: map()}
  end

  defmodule MapLit do
    @moduledoc "`mapOf(k to v, ...)` — map literal."
    defstruct [:entries, :meta]
    @type t :: %__MODULE__{entries: [{term(), term()}], meta: map()}
  end

  defmodule TupleAssign do
    @moduledoc "Tuple destructuring assignment: `{x, y} = expr`."
    defstruct [:names, :value, :meta]
    @type t :: %__MODULE__{names: [String.t()], value: term(), meta: map()}
  end

  defmodule TupleLit do
    @moduledoc "Tuple literal: `{a, b, ...}`."
    defstruct [:elements, :meta]
    @type t :: %__MODULE__{elements: [term()], meta: map()}
  end

  defmodule PairLit do
    @moduledoc "`Pair(a, b)` or `a to b` — tuple pair."
    defstruct [:first, :second, :meta]
    @type t :: %__MODULE__{first: term(), second: term(), meta: map()}
  end

  defmodule InOp do
    @moduledoc "`x in collection` — membership test."
    defstruct [:element, :collection, :meta]
    @type t :: %__MODULE__{element: term(), collection: term(), meta: map()}
  end

  # ── Type annotations ─────────────────────────────────────────────────

  defmodule TypeRef do
    @moduledoc "Type reference: `TypeName<Params>?`."
    defstruct [:name, :params, :nullable, :meta]
    @type t :: %__MODULE__{
            name: String.t(),
            params: [t()] | nil,
            nullable: boolean(),
            meta: map()
          }
  end

  defmodule FunctionType do
    @moduledoc "Function type: `(A, B) -> C`."
    defstruct [:param_types, :return_type, :meta]
    @type t :: %__MODULE__{param_types: [term()], return_type: term(), meta: map()}
  end
end
