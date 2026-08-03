defmodule Kore.Semantics.Exhaustive do
  @moduledoc """
  Exhaustiveness checking for `when` expressions over sealed types.

  For `when` whose subject's static type is a sealed type, require all variants
  or an `else` branch.
  """

  alias Kore.AST
  alias Kore.Errors

  @doc """
  Check exhaustiveness of `when` expressions.
  Returns `{:ok, ast}` or `{:error, errors}`.
  """
  def check(%AST.File{} = ast, file, source_lines) do
    sealed_types = collect_sealed_types(ast.module)
    errors = check_module(ast.module, sealed_types, file, source_lines)

    if errors == [] do
      {:ok, ast}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp collect_sealed_types(%AST.Module{declarations: decls}) do
    Enum.reduce(decls, %{}, fn
      %AST.SealedDecl{name: name, variants: variants}, acc ->
        variant_names = Enum.map(variants, & &1.name)
        Map.put(acc, name, variant_names)

      _, acc ->
        acc
    end)
  end

  defp check_module(%AST.Module{declarations: decls}, sealed_types, file, source_lines) do
    Enum.flat_map(decls, fn decl ->
      check_declaration(decl, sealed_types, file, source_lines)
    end)
  end

  defp check_declaration(%AST.FunDecl{body: body}, sealed_types, file, source_lines) do
    check_body(body, sealed_types, file, source_lines)
  end

  defp check_declaration(%AST.ValDecl{value: value}, sealed_types, file, source_lines) do
    check_expr(value, sealed_types, file, source_lines)
  end

  defp check_declaration(_decl, _sealed_types, _file, _source_lines), do: []

  defp check_body(%AST.Block{statements: stmts}, sealed_types, file, source_lines) do
    Enum.flat_map(stmts, &check_stmt(&1, sealed_types, file, source_lines))
  end

  defp check_body(expr, sealed_types, file, source_lines) when not is_nil(expr) do
    check_expr(expr, sealed_types, file, source_lines)
  end

  defp check_body(nil, _sealed_types, _file, _source_lines), do: []

  defp check_stmt(%AST.ValDecl{value: value}, sealed_types, file, source_lines) do
    check_expr(value, sealed_types, file, source_lines)
  end

  defp check_stmt(%AST.Assign{value: value}, sealed_types, file, source_lines) do
    check_expr(value, sealed_types, file, source_lines)
  end

  defp check_stmt(%AST.Return{value: value}, sealed_types, file, source_lines) do
    if value, do: check_expr(value, sealed_types, file, source_lines), else: []
  end

  defp check_stmt(expr, sealed_types, file, source_lines) do
    check_expr(expr, sealed_types, file, source_lines)
  end

  defp check_expr(%AST.When{branches: branches} = when_node, sealed_types, file, source_lines) do
    has_else = Enum.any?(branches, fn
      %AST.WhenBranch{pattern: %AST.PatternElse{}} -> true
      _ -> false
    end)

    is_patterns =
      Enum.flat_map(branches, fn
        %AST.WhenBranch{pattern: %AST.PatternIs{type_name: name}} -> [name]
        _ -> []
      end)

    errors =
      if not has_else and is_patterns != [] do
        Enum.flat_map(sealed_types, fn {sealed_name, variants} ->
          covered = Enum.filter(is_patterns, &(&1 in variants))

          if length(covered) > 0 and length(covered) < length(variants) do
            missing = variants -- covered
            line = Map.get(when_node.meta, :line, 1)
            col = Map.get(when_node.meta, :col, 1)
            source_line = Enum.at(source_lines, line - 1)

            [
              Errors.new(
                file, line, col,
                "non-exhaustive 'when' for sealed type '#{sealed_name}': missing variants #{inspect(missing)}. Add missing branches or an 'else' branch.",
                source_line
              )
            ]
          else
            []
          end
        end)
      else
        []
      end

    branch_errors =
      Enum.flat_map(branches, fn %AST.WhenBranch{body: body} ->
        check_body(body, sealed_types, file, source_lines)
      end)

    subject_errors = check_expr(when_node.subject, sealed_types, file, source_lines)
    errors ++ branch_errors ++ subject_errors
  end

  defp check_expr(%AST.If{condition: c, then_branch: t, else_branch: e}, sealed_types, file, source_lines) do
    check_expr(c, sealed_types, file, source_lines) ++
      check_body(t, sealed_types, file, source_lines) ++
      if(e, do: check_body(e, sealed_types, file, source_lines), else: [])
  end

  defp check_expr(%AST.BinOp{left: l, right: r}, sealed_types, file, source_lines) do
    check_expr(l, sealed_types, file, source_lines) ++
      check_expr(r, sealed_types, file, source_lines)
  end

  defp check_expr(%AST.Call{args: args}, sealed_types, file, source_lines) do
    Enum.flat_map(args, &check_expr(&1, sealed_types, file, source_lines))
  end

  defp check_expr(%AST.MethodCall{receiver: r, args: args}, sealed_types, file, source_lines) do
    check_expr(r, sealed_types, file, source_lines) ++
      Enum.flat_map(args, &check_expr(&1, sealed_types, file, source_lines))
  end

  defp check_expr(%AST.Lambda{body: body}, sealed_types, file, source_lines) do
    Enum.flat_map(body, &check_stmt(&1, sealed_types, file, source_lines))
  end

  defp check_expr(%AST.Block{} = block, sealed_types, file, source_lines) do
    check_body(block, sealed_types, file, source_lines)
  end

  defp check_expr(_other, _sealed_types, _file, _source_lines), do: []
end
