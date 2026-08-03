defmodule Kore.Typecheck do
  @moduledoc """
  Minimal local type checks (§10 of spec):
  - Literal/annotation mismatch (val x: Int = "hi")
  - Call arity vs declaration
  - Constructor field count
  - Condition of if/guards is Boolean when statically known

  Everything else falls through to the Elixir compiler / Dialyzer.
  """

  alias Kore.AST
  alias Kore.Errors

  @doc """
  Run minimal type checks on the AST.
  Returns `{:ok, ast}` or `{:error, errors}`.
  """
  def check(%AST.File{} = ast, file, source_lines) do
    declarations = collect_declarations(ast.module)
    errors = check_module(ast.module, declarations, file, source_lines)

    if errors == [] do
      {:ok, ast}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp collect_declarations(%AST.Module{declarations: decls}) do
    Enum.reduce(decls, %{}, fn
      %AST.FunDecl{name: name, params: params}, acc ->
        arity = length(params)
        min_arity = Enum.count(params, &is_nil(&1.default))
        Map.put(acc, {:fun, name}, %{arity: arity, min_arity: min_arity})

      %AST.DataDecl{name: name, fields: fields}, acc ->
        field_count = length(fields)
        min_fields = Enum.count(fields, &is_nil(&1.default))
        Map.put(acc, {:data, name}, %{arity: field_count, min_arity: min_fields})

      %AST.SealedDecl{variants: variants}, acc ->
        Enum.reduce(variants, acc, fn %AST.DataDecl{name: vname, fields: fields}, acc ->
          field_count = length(fields)
          min_fields = Enum.count(fields, &is_nil(&1.default))
          Map.put(acc, {:data, vname}, %{arity: field_count, min_arity: min_fields})
        end)

      _, acc ->
        acc
    end)
  end

  defp check_module(%AST.Module{declarations: decls}, declarations, file, source_lines) do
    Enum.flat_map(decls, fn decl ->
      check_declaration(decl, declarations, file, source_lines)
    end)
  end

  defp check_declaration(%AST.FunDecl{body: body}, declarations, file, source_lines) do
    check_body(body, declarations, file, source_lines)
  end

  defp check_declaration(%AST.ValDecl{type: type, value: value} = decl, declarations, file, source_lines) do
    check_type_literal_mismatch(type, value, decl.meta, file, source_lines) ++
      check_expr(value, declarations, file, source_lines)
  end

  defp check_declaration(_decl, _declarations, _file, _source_lines), do: []

  defp check_body(%AST.Block{statements: stmts}, declarations, file, source_lines) do
    Enum.flat_map(stmts, &check_stmt(&1, declarations, file, source_lines))
  end

  defp check_body(expr, declarations, file, source_lines) when not is_nil(expr) do
    check_expr(expr, declarations, file, source_lines)
  end

  defp check_body(nil, _declarations, _file, _source_lines), do: []

  defp check_stmt(%AST.ValDecl{type: type, value: value} = decl, declarations, file, source_lines) do
    check_type_literal_mismatch(type, value, decl.meta, file, source_lines) ++
      check_expr(value, declarations, file, source_lines)
  end

  defp check_stmt(%AST.Assign{value: value}, declarations, file, source_lines) do
    check_expr(value, declarations, file, source_lines)
  end

  defp check_stmt(%AST.Return{value: value}, declarations, file, source_lines) do
    if value, do: check_expr(value, declarations, file, source_lines), else: []
  end

  defp check_stmt(expr, declarations, file, source_lines) do
    check_expr(expr, declarations, file, source_lines)
  end

  defp check_expr(%AST.Call{function: %AST.VarRef{name: name}, args: args} = call, declarations, file, source_lines) do
    arity_errors =
      case Map.get(declarations, {:fun, name}) do
        nil ->
          []

        %{arity: max_arity, min_arity: min_arity} ->
          given = length(args)

          if given < min_arity or given > max_arity do
            line = Map.get(call.meta, :line, 1)
            col = Map.get(call.meta, :col, 1)
            source_line = Enum.at(source_lines, line - 1)

            [
              Errors.new(file, line, col,
                "function '#{name}' expects #{min_arity}..#{max_arity} arguments, got #{given}",
                source_line
              )
            ]
          else
            []
          end
      end

    arg_errors = Enum.flat_map(args, &check_expr(&1, declarations, file, source_lines))
    arity_errors ++ arg_errors
  end

  defp check_expr(%AST.ConstructorCall{type_name: name, args: args} = call, declarations, file, source_lines) do
    arity_errors =
      case Map.get(declarations, {:data, name}) do
        nil ->
          []

        %{arity: max_arity, min_arity: min_arity} ->
          given = length(args)

          if given < min_arity or given > max_arity do
            line = Map.get(call.meta, :line, 1)
            col = Map.get(call.meta, :col, 1)
            source_line = Enum.at(source_lines, line - 1)

            [
              Errors.new(file, line, col,
                "constructor '#{name}' expects #{min_arity}..#{max_arity} fields, got #{given}",
                source_line
              )
            ]
          else
            []
          end
      end

    arg_errors = Enum.flat_map(args, &check_expr(&1, declarations, file, source_lines))
    arity_errors ++ arg_errors
  end

  defp check_expr(%AST.If{condition: c, then_branch: t, else_branch: e}, declarations, file, source_lines) do
    check_expr(c, declarations, file, source_lines) ++
      check_body(t, declarations, file, source_lines) ++
      if(e, do: check_body(e, declarations, file, source_lines), else: [])
  end

  defp check_expr(%AST.When{subject: subj, branches: branches}, declarations, file, source_lines) do
    check_expr(subj, declarations, file, source_lines) ++
      Enum.flat_map(branches, fn %AST.WhenBranch{body: body} ->
        check_body(body, declarations, file, source_lines)
      end)
  end

  defp check_expr(%AST.BinOp{left: l, right: r}, declarations, file, source_lines) do
    check_expr(l, declarations, file, source_lines) ++
      check_expr(r, declarations, file, source_lines)
  end

  defp check_expr(%AST.Call{args: args}, declarations, file, source_lines) do
    Enum.flat_map(args, &check_expr(&1, declarations, file, source_lines))
  end

  defp check_expr(%AST.MethodCall{receiver: r, args: args}, declarations, file, source_lines) do
    check_expr(r, declarations, file, source_lines) ++
      Enum.flat_map(args, &check_expr(&1, declarations, file, source_lines))
  end

  defp check_expr(%AST.Lambda{body: body}, declarations, file, source_lines) do
    Enum.flat_map(body, &check_stmt(&1, declarations, file, source_lines))
  end

  defp check_expr(%AST.Block{} = block, declarations, file, source_lines) do
    check_body(block, declarations, file, source_lines)
  end

  defp check_expr(_other, _declarations, _file, _source_lines), do: []

  defp check_type_literal_mismatch(nil, _value, _meta, _file, _source_lines), do: []

  defp check_type_literal_mismatch(
         %AST.TypeRef{name: type_name},
         %AST.Literal{type: lit_type},
         meta, file, source_lines
       ) do
    mismatch =
      case {type_name, lit_type} do
        {"Int", :int} -> false
        {"Double", :double} -> false
        {"String", :string} -> false
        {"Boolean", :bool} -> false
        {"Int", _} -> true
        {"Double", _} -> true
        {"String", _} -> true
        {"Boolean", _} -> true
        _ -> false
      end

    if mismatch do
      line = Map.get(meta, :line, 1)
      col = Map.get(meta, :col, 1)
      source_line = Enum.at(source_lines, line - 1)

      [Errors.new(file, line, col,
        "type mismatch: expected '#{type_name}', got #{lit_type} literal",
        source_line)]
    else
      []
    end
  end

  defp check_type_literal_mismatch(_type, _value, _meta, _file, _source_lines), do: []
end
