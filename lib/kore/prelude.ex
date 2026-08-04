defmodule Kore.Prelude do
  @moduledoc """
  Prelude mapping table — compile-time rewriting of KorE method calls
  to their Elixir equivalents.

  This is NOT a runtime library. Method-call syntax `recv.name(args)` is
  looked up here during codegen. Only helpers with no direct Elixir equivalent
  generate into `Kore.Runtime`.
  """

  @doc """
  Look up a method call in the prelude table.
  Returns `{:ok, {module, function, arg_transform}}` or `:none`.

  `arg_transform` is one of:
  - `:receiver_first` — `recv.method(args)` → `Module.func(recv, args...)`
  - `:receiver_last`  — `recv.method(args)` → `Module.func(args..., recv)`
  - `{:receiver_first, :property}` — `recv.prop` → `Module.func(recv)`
  - `:fold_reorder`   — special handling for fold/reduce arg reorder
  - `:contains_to_in` — `list.contains(x)` → `x in list`
  """
  def lookup_method(method_name, arity \\ nil) do
    case {method_name, arity} do
      # ── List/Enum methods ────────────────────────────────────────
      {"map", _} -> {:ok, {"Enum", "map", :receiver_first}}
      {"filter", _} -> {:ok, {"Enum", "filter", :receiver_first}}
      {"forEach", _} -> {:ok, {"Enum", "each", :receiver_first}}
      {"fold", _} -> {:ok, {"Enum", "reduce", :fold_reorder}}
      {"first", _} -> {:ok, {"List", "first", :receiver_first}}
      {"last", _} -> {:ok, {"List", "last", :receiver_first}}
      {"isEmpty", _} -> {:ok, {"Enum", "empty?", :receiver_first}}
      {"contains", _} -> {:ok, {nil, "in", :contains_to_in}}
      {"reversed", _} -> {:ok, {"Enum", "reverse", :receiver_first}}
      {"sorted", _} -> {:ok, {"Enum", "sort", :receiver_first}}
      {"joinToString", _} -> {:ok, {"Enum", "join", :receiver_first}}
      {"size", nil} -> {:ok, {nil, "length", {:receiver_first, :property}}}
      {"plus", _} -> {:ok, {nil, "++", :list_append}}
      {"plusAll", _} -> {:ok, {nil, "++", :list_concat}}
      {"take", _} -> {:ok, {"Enum", "take", :receiver_first}}
      {"drop", _} -> {:ok, {"Enum", "drop", :receiver_first}}
      {"sum", _} -> {:ok, {"Enum", "sum", :receiver_first}}
      {"count", _} -> {:ok, {"Enum", "count", :receiver_first}}
      {"any", _} -> {:ok, {"Enum", "any?", :receiver_first}}
      {"all", _} -> {:ok, {"Enum", "all?", :receiver_first}}
      {"flatMap", _} -> {:ok, {"Enum", "flat_map", :receiver_first}}
      {"distinct", _} -> {:ok, {"Enum", "uniq", :receiver_first}}

      # ── String methods ──────────────────────────────────────────
      {"length", nil} -> {:ok, {"String", "length", {:receiver_first, :property}}}
      {"uppercase", _} -> {:ok, {"String", "upcase", :receiver_first}}
      {"lowercase", _} -> {:ok, {"String", "downcase", :receiver_first}}
      {"trim", _} -> {:ok, {"String", "trim", :receiver_first}}
      {"split", _} -> {:ok, {"String", "split", :receiver_first}}
      {"startsWith", _} -> {:ok, {"String", "starts_with?", :receiver_first}}
      {"endsWith", _} -> {:ok, {"String", "ends_with?", :receiver_first}}
      {"includes", _} -> {:ok, {"String", "contains?", :receiver_first}}
      {"replace", _} -> {:ok, {"String", "replace", :receiver_first}}
      {"toInt", _} -> {:ok, {"String", "to_integer", :receiver_first}}
      {"toDouble", _} -> {:ok, {"String", "to_float", :receiver_first}}
      {"toString", _} -> {:ok, {nil, "to_string", :receiver_first}}

      # ── Map methods ────────────────────────────────────────────
      {"get", _} -> {:ok, {"Map", "get", :receiver_first}}
      {"put", _} -> {:ok, {"Map", "put", :receiver_first}}
      {"remove", _} -> {:ok, {"Map", "delete", :receiver_first}}
      {"containsKey", _} -> {:ok, {"Map", "has_key?", :receiver_first}}
      {"keys", nil} -> {:ok, {"Map", "keys", {:receiver_first, :property}}}
      {"values", nil} -> {:ok, {"Map", "values", {:receiver_first, :property}}}
      {"mapSize", nil} -> {:ok, {nil, "map_size", {:receiver_first, :property}}}

      # ── Process methods ────────────────────────────────────────
      {"send", _} -> {:ok, {nil, "send", :send_rewrite}}

      _ -> :none
    end
  end

  @doc """
  Look up a top-level function call in the prelude.
  Returns `{:ok, {module, function}}` or `:none`.
  """
  def lookup_function(name, _arity \\ nil) do
    case name do
      "println" -> {:ok, {"IO", "puts"}}
      "print" -> {:ok, {"IO", "write"}}
      "readLine" -> {:ok, :read_line}
      "self" -> {:ok, {nil, "self"}}
      "listOf" -> {:ok, :list_literal}
      "mapOf" -> {:ok, :map_literal}
      "tupleOf" -> {:ok, :tuple_literal}
      _ -> :none
    end
  end

  @doc """
  Look up a static method call on a module (e.g. Conn.getMethod).
  Returns `{:ok, transform}` or `:none`.
  """
  def lookup_static_method(mod_name, method_name, arity \\ nil) do
    case {mod_name, method_name, arity} do
      {"Conn", "getMethod", 1} -> {:ok, {:struct_field, "method"}}
      {"Conn", "getPathInfo", 1} -> {:ok, {:struct_field, "path_info"}}
      {"Conn", "readBody", 1} -> {:ok, :read_body}
      _ -> :none
    end
  end

  @doc """
  Convert a KorE lowerCamelCase name to Elixir snake_case.
  """
  def to_snake_case(name) when is_binary(name) do
    name
    |> String.graphemes()
    |> Enum.reduce({"", false}, fn char, {acc, prev_was_upper} ->
      if char >= "A" and char <= "Z" do
        lower = String.downcase(char)

        if acc == "" do
          {lower, true}
        else
          if prev_was_upper do
            {acc <> lower, true}
          else
            {acc <> "_" <> lower, true}
          end
        end
      else
        {acc <> char, false}
      end
    end)
    |> elem(0)
  end

  @doc """
  Convert a KorE UpperCamelCase type name to snake_case (for file names).
  """
  def type_to_snake_case(name) when is_binary(name) do
    to_snake_case(name)
  end
end
