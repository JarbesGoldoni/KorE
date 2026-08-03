defmodule Kore.Formatter do
  @moduledoc """
  Code formatter for KorE source code.

  Parses KorE source code to AST and pretty-prints it back into standardized KorE syntax.
  """

  alias Kore.{Lexer, Parser, AST}

  @doc """
  Format KorE source code string.
  Returns `{:ok, formatted_code}` or `{:error, errors}`.
  """
  def format(source, file \\ "nofile") do
    source_lines = String.split(source, "\n")

    with {:ok, tokens} <- Lexer.tokenize(source, file),
         {:ok, ast} <- Parser.parse(tokens, file, source_lines) do
      {:ok, format_file_ast(ast)}
    end
  end

  @doc """
  Format a .kore file on disk. If `overwrite: true`, writes formatted content back to file.
  """
  def format_file(path, opts \\ []) do
    source = File.read!(path)

    case format(source, path) do
      {:ok, formatted} ->
        if Keyword.get(opts, :overwrite, false) and formatted != source do
          File.write!(path, formatted)
        end

        {:ok, formatted}

      error ->
        error
    end
  end

  # ── AST to KorE Source Pretty-Printer ──────────────────────────────

  defp format_file_ast(%AST.File{imports: imports, module: module}) do
    imports_str =
      (imports || [])
      |> Enum.map(&format_import/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    module_str = format_module(module)

    if imports_str != "" do
      imports_str <> "\n\n" <> module_str <> "\n"
    else
      module_str <> "\n"
    end
  end

  defp format_import(%AST.Import{path: path}) do
    "import " <> Enum.join(path, ".")
  end

  defp format_module(%AST.Module{name: name, declarations: decls}) do
    decls_str =
      (decls || [])
      |> Enum.map(&format_decl/1)
      |> Enum.join("\n\n")

    """
    module #{name} {
    #{indent(decls_str)}
    }
    """
    |> String.trim_trailing()
  end

  defp format_decl(%AST.FunDecl{name: name, params: params, return_type: ret_type, body: body}) do
    params_str = (params || []) |> Enum.map(&format_param/1) |> Enum.join(", ")
    ret_str = if ret_type, do: ": #{format_type(ret_type)}", else: ""

    case body do
      %AST.Block{statements: stmts} ->
        stmts_str = Enum.map(stmts, &format_stmt/1) |> Enum.join("\n")

        """
        fun #{name}(#{params_str})#{ret_str} {
        #{indent(stmts_str)}
        }
        """
        |> String.trim_trailing()

      expr ->
        "fun #{name}(#{params_str})#{ret_str} = #{format_expr(expr)}"
    end
  end

  defp format_decl(%AST.DataDecl{name: name, fields: fields}) do
    fields_str = (fields || []) |> Enum.map(&format_data_field/1) |> Enum.join(", ")
    "data #{name}(#{fields_str})"
  end

  defp format_decl(%AST.SealedDecl{name: name, variants: variants}) do
    vars_str = (variants || []) |> Enum.map(&format_decl/1) |> Enum.join("\n")

    """
    sealed #{name} {
    #{indent(vars_str)}
    }
    """
    |> String.trim_trailing()
  end

  defp format_decl(%AST.ActorDecl{name: name, fields: fields, methods: methods}) do
    fields_str = (fields || []) |> Enum.map(&format_actor_field/1) |> Enum.join(", ")
    methods_str = (methods || []) |> Enum.map(&format_decl/1) |> Enum.join("\n\n")

    """
    actor #{name}(#{fields_str}) {
    #{indent(methods_str)}
    }
    """
    |> String.trim_trailing()
  end

  defp format_decl(%AST.ValDecl{name: name, type: type, value: val, mutable: mutable}) do
    keyword = if mutable, do: "var", else: "val"
    type_str = if type, do: ": #{format_type(type)}", else: ""
    "#{keyword} #{name}#{type_str} = #{format_expr(val)}"
  end

  defp format_param(%AST.Param{name: name, type: type, default: default}) do
    def_str = if default, do: " = #{format_expr(default)}", else: ""
    "#{name}: #{format_type(type)}#{def_str}"
  end

  defp format_data_field(%AST.DataField{name: name, type: type, default: default}) do
    def_str = if default, do: " = #{format_expr(default)}", else: ""
    "val #{name}: #{format_type(type)}#{def_str}"
  end

  defp format_actor_field(%AST.ActorField{name: name, type: type, default: default, mutable: mutable}) do
    kw = if mutable, do: "var", else: "val"
    def_str = if default, do: " = #{format_expr(default)}", else: ""
    "#{kw} #{name}: #{format_type(type)}#{def_str}"
  end

  defp format_type(%AST.TypeRef{name: name, params: params, nullable: nullable}) do
    params_str =
      if params && params != [] do
        "<" <> (Enum.map(params, &format_type/1) |> Enum.join(", ")) <> ">"
      else
        ""
      end

    null_str = if nullable, do: "?", else: ""
    "#{name}#{params_str}#{null_str}"
  end

  defp format_type(%AST.FunctionType{param_types: pts, return_type: rt}) do
    pts_str = Enum.map(pts, &format_type/1) |> Enum.join(", ")
    "(#{pts_str}) -> #{format_type(rt)}"
  end

  defp format_type(other) when is_binary(other), do: other
  defp format_type(other), do: to_string(other)

  # ── Statements and Expressions ─────────────────────────────────────

  defp format_stmt(%AST.ValDecl{} = d), do: format_decl(d)
  defp format_stmt(%AST.Assign{name: name, value: val}), do: "#{name} = #{format_expr(val)}"
  defp format_stmt(%AST.Return{value: nil}), do: "return"
  defp format_stmt(%AST.Return{value: val}), do: "return #{format_expr(val)}"
  defp format_stmt(expr), do: format_expr(expr)

  defp format_expr(%AST.Literal{type: :string, value: v}), do: "\"#{v}\""
  defp format_expr(%AST.Literal{type: :null}), do: "null"
  defp format_expr(%AST.Literal{type: :atom, value: v}), do: ":#{v}"
  defp format_expr(%AST.Literal{value: v}), do: to_string(v)

  defp format_expr(%AST.VarRef{name: name}), do: name

  defp format_expr(%AST.BinOp{op: op, left: l, right: r}) do
    op_str = format_binop_symbol(op)
    "#{format_expr(l)} #{op_str} #{format_expr(r)}"
  end

  defp format_expr(%AST.UnaryOp{op: op, operand: o}) do
    "#{op}#{format_expr(o)}"
  end

  defp format_expr(%AST.If{condition: cond_expr, then_branch: then_b, else_branch: else_b}) do
    cond_str = format_expr(cond_expr)

    if is_map(then_b) and then_b.__struct__ == AST.Block do
      then_str = format_stmt(then_b)

      else_str =
        if else_b do
          "\nelse " <>
            if is_map(else_b) and else_b.__struct__ == AST.Block do
              format_stmt(else_b)
            else
              "{\n#{indent(format_stmt(else_b))}\n}"
            end
        else
          ""
        end

      "if (#{cond_str}) #{then_str}#{else_str}"
    else
      if else_b do
        "if (#{cond_str}) #{format_expr(then_b)} else #{format_expr(else_b)}"
      else
        "if (#{cond_str}) #{format_expr(then_b)}"
      end
    end
  end

  defp format_expr(%AST.When{subject: subj, branches: branches}) do
    branches_str = Enum.map(branches, &format_when_branch/1) |> Enum.join("\n")

    """
    when (#{format_expr(subj)}) {
    #{indent(branches_str)}
    }
    """
    |> String.trim_trailing()
  end

  defp format_expr(%AST.Lambda{params: params, body: body}) do
    params_str =
      if params && params != [] do
        Enum.join(params, ", ") <> " -> "
      else
        ""
      end

    body_str = Enum.map(body, &format_stmt/1) |> Enum.join("\n")

    """
    { #{params_str}
    #{indent(body_str)}
    }
    """
    |> String.trim_trailing()
  end

  defp format_expr(%AST.Call{function: fun, args: args, trailing_lambda: tl}) do
    args_str = Enum.map(args, &format_expr/1) |> Enum.join(", ")
    fun_str = format_expr(fun)
    tl_str = if tl, do: " " <> format_expr(tl), else: ""
    "#{fun_str}(#{args_str})#{tl_str}"
  end

  defp format_expr(%AST.MethodCall{receiver: r, method: m, args: args, trailing_lambda: tl}) do
    args_str = Enum.map(args, &format_expr/1) |> Enum.join(", ")
    recv_str = format_expr(r)
    tl_str = if tl, do: " " <> format_expr(tl), else: ""
    "#{recv_str}.#{m}(#{args_str})#{tl_str}"
  end

  defp format_expr(%AST.FieldAccess{receiver: r, field: f}), do: "#{format_expr(r)}.#{f}"
  defp format_expr(%AST.SafeAccess{receiver: r, field: f}), do: "#{format_expr(r)}?.#{f}"
  defp format_expr(%AST.Elvis{left: l, right: r}), do: "#{format_expr(l)} ?: #{format_expr(r)}"
  defp format_expr(%AST.NotNull{expr: e}), do: "#{format_expr(e)}!!"

  defp format_expr(%AST.ConstructorCall{type_name: t, args: args}) do
    args_str = Enum.map(args, &format_expr/1) |> Enum.join(", ")
    "#{t}(#{args_str})"
  end

  defp format_expr(%AST.CopyCall{receiver: r, updates: u}) do
    u_str = Enum.map(u, fn {k, v} -> "#{k} = #{format_expr(v)}" end) |> Enum.join(", ")
    "#{format_expr(r)}.copy(#{u_str})"
  end

  defp format_expr(%AST.StringInterp{parts: parts}) do
    res =
      Enum.map(parts, fn
        {:string, s} -> s
        {:expr, %AST.VarRef{name: n}} -> "$#{n}"
        {:expr, e} -> "${#{format_expr(e)}}"
      end)
      |> Enum.join("")

    "\"#{res}\""
  end

  defp format_expr(%AST.Spawn{body: body}) do
    "spawn #{format_expr(body)}"
  end

  defp format_expr(%AST.Receive{branches: branches}) do
    branches_str = Enum.map(branches, &format_when_branch/1) |> Enum.join("\n")

    """
    receive {
    #{indent(branches_str)}
    }
    """
    |> String.trim_trailing()
  end

  defp format_expr(%AST.For{var: v, iterable: i, body: body}) do
    """
    for (#{v} in #{format_expr(i)}) #{format_stmt(body)}
    """
    |> String.trim_trailing()
  end

  defp format_expr(%AST.Range{from: f, to: t}), do: "#{format_expr(f)}..#{format_expr(t)}"
  defp format_expr(%AST.ListLit{elements: e}), do: "listOf(" <> (Enum.map(e, &format_expr/1) |> Enum.join(", ")) <> ")"
  defp format_expr(%AST.MapLit{entries: entries}) do
    en = Enum.map(entries, fn {k, v} -> "#{format_expr(k)} to #{format_expr(v)}" end) |> Enum.join(", ")
    "mapOf(#{en})"
  end
  defp format_expr(%AST.PairLit{first: a, second: b}), do: "#{format_expr(a)} to #{format_expr(b)}"
  defp format_expr(%AST.InOp{element: e, collection: c}), do: "#{format_expr(e)} in #{format_expr(c)}"

  defp format_expr(%AST.Block{statements: stmts}) do
    stmts_str = Enum.map(stmts, &format_stmt/1) |> Enum.join("\n")

    """
    {
    #{indent(stmts_str)}
    }
    """
    |> String.trim_trailing()
  end

  defp format_when_branch(%AST.WhenBranch{pattern: p, body: b}) do
    pat_str = format_pattern(p)

    body_str =
      if is_map(b) and b.__struct__ == AST.Block do
        format_stmt(b)
      else
        format_expr(b)
      end

    "#{pat_str} -> #{body_str}"
  end

  defp format_pattern(%AST.PatternIs{type_name: t, bindings: b}) do
    binds_str = if b, do: "(" <> Enum.map_join(b, ", ", &("val " <> &1)) <> ")", else: ""
    "is #{t}#{binds_str}"
  end

  defp format_pattern(%AST.PatternValue{values: v}) do
    Enum.map(v, &format_expr/1) |> Enum.join(", ")
  end

  defp format_pattern(%AST.PatternElse{}), do: "else"

  defp format_binop_symbol(op) when is_atom(op) do
    case op do
      :plus -> "+"
      :minus -> "-"
      :star -> "*"
      :slash -> "/"
      :percent -> "%"
      :eq_eq -> "=="
      :not_eq -> "!="
      :less -> "<"
      :greater -> ">"
      :less_eq -> "<="
      :greater_eq -> ">="
      :and_and -> "&&"
      :or_or -> "||"
      :elvis -> "?:"
      :range -> ".."
      :equal -> "="
      :plus_eq -> "+="
      :minus_eq -> "-="
      other -> to_string(other)
    end
  end

  defp indent(str) do
    str
    |> String.split("\n")
    |> Enum.map(&("    " <> &1))
    |> Enum.join("\n")
  end
end
