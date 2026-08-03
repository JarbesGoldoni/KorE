defmodule Kore.Semantics.Closures do
  @moduledoc """
  Closure check pass.

  Walk lambdas; any assignment to an outer `var` inside a lambda → compile error:
  "cannot rebind 'x' inside a lambda: BEAM closures capture values, not variables"
  """

  alias Kore.AST
  alias Kore.Errors

  @doc """
  Check that no lambda body reassigns an outer var.
  Returns `{:ok, ast}` or `{:error, errors}`.
  """
  def check(%AST.File{} = ast, file, source_lines) do
    errors = check_module(ast.module, file, source_lines, MapSet.new())

    if errors == [] do
      {:ok, ast}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp check_module(%AST.Module{declarations: decls}, file, source_lines, _outer_vars) do
    Enum.flat_map(decls, fn decl ->
      check_declaration(decl, file, source_lines, MapSet.new())
    end)
  end

  defp check_declaration(%AST.FunDecl{body: body}, file, source_lines, _outer_vars) do
    # The function body establishes a new var scope
    check_body(body, file, source_lines, MapSet.new(), false)
  end

  defp check_declaration(%AST.ValDecl{value: value}, file, source_lines, outer_vars) do
    check_expr(value, file, source_lines, outer_vars, false)
  end

  defp check_declaration(_decl, _file, _source_lines, _outer_vars), do: []

  defp check_body(%AST.Block{statements: stmts}, file, source_lines, outer_vars, in_lambda) do
    {_vars, errors} =
      Enum.reduce(stmts, {outer_vars, []}, fn stmt, {vars, errors} ->
        {new_vars, new_errors} = check_statement(stmt, file, source_lines, vars, in_lambda)
        {new_vars, errors ++ new_errors}
      end)

    errors
  end

  defp check_body(expr, file, source_lines, outer_vars, in_lambda) when not is_nil(expr) do
    check_expr(expr, file, source_lines, outer_vars, in_lambda)
  end

  defp check_body(nil, _file, _source_lines, _outer_vars, _in_lambda), do: []

  defp check_statement(%AST.ValDecl{name: name, value: value, mutable: mutable}, file, source_lines, vars, in_lambda) do
    errors = check_expr(value, file, source_lines, vars, in_lambda)
    new_vars = if mutable, do: MapSet.put(vars, name), else: vars
    {new_vars, errors}
  end

  defp check_statement(%AST.Assign{name: name, value: value} = assign, file, source_lines, vars, in_lambda) do
    errors = check_expr(value, file, source_lines, vars, in_lambda)

    if in_lambda and MapSet.member?(vars, name) do
      line = Map.get(assign.meta, :line, 1)
      col = Map.get(assign.meta, :col, 1)
      source_line = Enum.at(source_lines, line - 1)

      err =
        Errors.new(
          file,
          line,
          col,
          "cannot rebind '#{name}' inside a lambda: BEAM closures capture values, not variables",
          source_line
        )

      {vars, errors ++ [err]}
    else
      {vars, errors}
    end
  end

  defp check_statement(%AST.Return{value: value}, file, source_lines, vars, in_lambda) do
    errors = if value, do: check_expr(value, file, source_lines, vars, in_lambda), else: []
    {vars, errors}
  end

  defp check_statement(expr, file, source_lines, vars, in_lambda) do
    errors = check_expr(expr, file, source_lines, vars, in_lambda)
    {vars, errors}
  end

  defp check_expr(%AST.Lambda{params: params, body: body}, file, source_lines, outer_vars, _in_lambda) do
    # Inside a lambda, the outer vars are now "captured" — reassignment is forbidden
    lambda_vars =
      case params do
        nil -> outer_vars
        names when is_list(names) -> Enum.reduce(names, outer_vars, &MapSet.delete(&2, &1))
      end

    Enum.flat_map(body, fn stmt ->
      {_vars, errors} = check_statement(stmt, file, source_lines, lambda_vars, true)
      errors
    end)
  end

  defp check_expr(%AST.BinOp{left: left, right: right}, file, source_lines, vars, in_lambda) do
    check_expr(left, file, source_lines, vars, in_lambda) ++
      check_expr(right, file, source_lines, vars, in_lambda)
  end

  defp check_expr(%AST.UnaryOp{operand: operand}, file, source_lines, vars, in_lambda) do
    check_expr(operand, file, source_lines, vars, in_lambda)
  end

  defp check_expr(%AST.Call{function: fun, args: args, trailing_lambda: tl}, file, source_lines, vars, in_lambda) do
    check_expr(fun, file, source_lines, vars, in_lambda) ++
      Enum.flat_map(args, &check_expr(&1, file, source_lines, vars, in_lambda)) ++
      if(tl, do: check_expr(tl, file, source_lines, vars, in_lambda), else: [])
  end

  defp check_expr(%AST.MethodCall{receiver: recv, args: args, trailing_lambda: tl}, file, source_lines, vars, in_lambda) do
    check_expr(recv, file, source_lines, vars, in_lambda) ++
      Enum.flat_map(args, &check_expr(&1, file, source_lines, vars, in_lambda)) ++
      if(tl, do: check_expr(tl, file, source_lines, vars, in_lambda), else: [])
  end

  defp check_expr(%AST.If{condition: cond_expr, then_branch: then_b, else_branch: else_b}, file, source_lines, vars, in_lambda) do
    check_expr(cond_expr, file, source_lines, vars, in_lambda) ++
      check_body(then_b, file, source_lines, vars, in_lambda) ++
      if(else_b, do: check_body(else_b, file, source_lines, vars, in_lambda), else: [])
  end

  defp check_expr(%AST.When{subject: subj, branches: branches}, file, source_lines, vars, in_lambda) do
    check_expr(subj, file, source_lines, vars, in_lambda) ++
      Enum.flat_map(branches, fn %AST.WhenBranch{body: body} ->
        check_body(body, file, source_lines, vars, in_lambda)
      end)
  end

  defp check_expr(%AST.Block{} = block, file, source_lines, vars, in_lambda) do
    check_body(block, file, source_lines, vars, in_lambda)
  end

  defp check_expr(%AST.For{iterable: iter, body: body}, file, source_lines, vars, in_lambda) do
    check_expr(iter, file, source_lines, vars, in_lambda) ++
      check_body(body, file, source_lines, vars, in_lambda)
  end

  defp check_expr(%AST.FieldAccess{receiver: r}, file, source_lines, vars, in_lambda) do
    check_expr(r, file, source_lines, vars, in_lambda)
  end

  defp check_expr(%AST.SafeAccess{receiver: r}, file, source_lines, vars, in_lambda) do
    check_expr(r, file, source_lines, vars, in_lambda)
  end

  defp check_expr(%AST.Elvis{left: l, right: r}, file, source_lines, vars, in_lambda) do
    check_expr(l, file, source_lines, vars, in_lambda) ++
      check_expr(r, file, source_lines, vars, in_lambda)
  end

  defp check_expr(%AST.NotNull{expr: e}, file, source_lines, vars, in_lambda) do
    check_expr(e, file, source_lines, vars, in_lambda)
  end

  defp check_expr(%AST.ConstructorCall{args: args}, file, source_lines, vars, in_lambda) do
    Enum.flat_map(args, &check_expr(&1, file, source_lines, vars, in_lambda))
  end

  defp check_expr(%AST.StringInterp{parts: parts}, file, source_lines, vars, in_lambda) do
    Enum.flat_map(parts, fn
      {:expr, expr} -> check_expr(expr, file, source_lines, vars, in_lambda)
      _ -> []
    end)
  end

  defp check_expr(%AST.Spawn{body: body}, file, source_lines, vars, in_lambda) do
    check_body(body, file, source_lines, vars, in_lambda)
  end

  defp check_expr(%AST.Receive{branches: branches}, file, source_lines, vars, in_lambda) do
    Enum.flat_map(branches, fn %AST.WhenBranch{body: body} ->
      check_body(body, file, source_lines, vars, in_lambda)
    end)
  end

  defp check_expr(_other, _file, _source_lines, _vars, _in_lambda), do: []
end
