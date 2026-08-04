defmodule Kore.Semantics.Scopes do
  @moduledoc """
  Name resolution and scoping pass.

  Resolves every VarRef; classifies val/var; errors on:
  - undefined name
  - val reassignment
  - duplicate declaration in same scope
  """

  alias Kore.AST
  alias Kore.Errors

  @doc """
  Resolve names and validate scoping rules on the AST.
  Returns `{:ok, ast}` or `{:error, errors}`.
  """
  def resolve(%AST.File{} = ast, file, source_lines) do
    errors = []
    scope = %{vars: %{}, parent: nil}

    scope = Enum.reduce(ast.imports || [], scope, fn %AST.Import{path: path}, scope ->
      imported_name = List.last(path)
      put_var(scope, imported_name, :import)
    end)

    {_scope, errors} = resolve_module(ast.module, scope, file, source_lines, errors)

    if errors == [] do
      {:ok, ast}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp resolve_module(%AST.Module{} = mod, scope, file, source_lines, errors) do
    name_errors = check_file_module_name(mod, file, source_lines)
    errors = errors ++ name_errors

    # First pass: collect all declaration names (functions, data, sealed, actors)
    scope = collect_declarations(mod.declarations, scope)
    # Second pass: resolve bodies
    Enum.reduce(mod.declarations, {scope, errors}, fn decl, {scope, errors} ->
      resolve_declaration(decl, scope, file, source_lines, errors)
    end)
  end

  defp collect_declarations(decls, scope) do
    Enum.reduce(decls, scope, fn
      %AST.FunDecl{name: name}, scope ->
        put_var(scope, name, :fun)

      %AST.DataDecl{name: name}, scope ->
        put_var(scope, name, :data)

      %AST.SealedDecl{name: name, variants: variants}, scope ->
        scope = put_var(scope, name, :sealed)
        Enum.reduce(variants, scope, fn %AST.DataDecl{name: vname}, scope ->
          put_var(scope, vname, :data)
        end)

      %AST.ActorDecl{name: name}, scope ->
        put_var(scope, name, :actor)

      %AST.ValDecl{name: name, mutable: mutable}, scope ->
        put_var(scope, name, if(mutable, do: :var, else: :val))

      _, scope ->
        scope
    end)
  end

  defp resolve_declaration(%AST.FunDecl{} = fun, scope, file, source_lines, errors) do
    early_return_errors = check_early_returns(fun.body, file, source_lines)
    errors = errors ++ early_return_errors

    # Create a new scope for the function body with params
    fun_scope = push_scope(scope)

    fun_scope =
      Enum.reduce(fun.params, fun_scope, fn %AST.Param{name: name}, scope ->
        put_var(scope, name, :val)
      end)

    {_scope, errors} = resolve_body(fun.body, fun_scope, file, source_lines, errors)
    {scope, errors}
  end

  defp resolve_declaration(%AST.ValDecl{} = decl, scope, file, source_lines, errors) do
    {_scope, errors} = resolve_expr(decl.value, scope, file, source_lines, errors)
    kind = if decl.mutable, do: :var, else: :val
    scope = put_var(scope, decl.name, kind)
    {scope, errors}
  end

  defp resolve_declaration(_decl, scope, _file, _source_lines, errors) do
    {scope, errors}
  end

  defp resolve_body(%AST.Block{statements: stmts}, scope, file, source_lines, errors) do
    body_scope = push_scope(scope)

    Enum.reduce(stmts, {body_scope, errors}, fn stmt, {scope, errors} ->
      resolve_statement(stmt, scope, file, source_lines, errors)
    end)
  end

  defp resolve_body(expr, scope, file, source_lines, errors) when not is_nil(expr) do
    resolve_expr(expr, scope, file, source_lines, errors)
  end

  defp resolve_body(nil, scope, _file, _source_lines, errors) do
    {scope, errors}
  end

  defp resolve_statement(%AST.ValDecl{} = decl, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(decl.value, scope, file, source_lines, errors)
    kind = if decl.mutable, do: :var, else: :val

    case get_var_local(scope, decl.name) do
      nil ->
        {put_var(scope, decl.name, kind), errors}

      _exists ->
        err = make_error(file, decl.meta, "duplicate declaration '#{decl.name}' in same scope", source_lines)
        {put_var(scope, decl.name, kind), [err | errors]}
    end
  end

  defp resolve_statement(%AST.Assign{} = assign, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(assign.value, scope, file, source_lines, errors)

    case get_var(scope, assign.name) do
      nil ->
        err = make_error(file, assign.meta, "undefined variable '#{assign.name}'", source_lines)
        {scope, [err | errors]}

      :val ->
        err = make_error(file, assign.meta, "cannot reassign 'val' variable '#{assign.name}'", source_lines)
        {scope, [err | errors]}

      :var ->
        {scope, errors}

      _ ->
        {scope, errors}
    end
  end

  defp resolve_statement(%AST.Return{value: value}, scope, file, source_lines, errors) do
    if value do
      resolve_expr(value, scope, file, source_lines, errors)
    else
      {scope, errors}
    end
  end

  defp resolve_statement(expr, scope, file, source_lines, errors) do
    resolve_expr(expr, scope, file, source_lines, errors)
  end

  defp resolve_expr(%AST.VarRef{name: name} = ref, scope, file, source_lines, errors) do
    case get_var(scope, name) do
      nil ->
        # Could be a built-in function (println, listOf, etc.) or module reference (Plug.Cowboy, Kore.Main)
        first_char = String.at(name, 0)
        is_module_ref = (first_char >= "A" and first_char <= "Z") or String.contains?(name, ".")

        if builtin?(name) or is_module_ref do
          {scope, errors}
        else
          err = make_error(file, ref.meta, "undefined variable '#{name}'", source_lines)
          {scope, [err | errors]}
        end

      _ ->
        {scope, errors}
    end
  end

  defp resolve_expr(%AST.BinOp{left: left, right: right}, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(left, scope, file, source_lines, errors)
    resolve_expr(right, scope, file, source_lines, errors)
  end

  defp resolve_expr(%AST.UnaryOp{operand: operand}, scope, file, source_lines, errors) do
    resolve_expr(operand, scope, file, source_lines, errors)
  end

  defp resolve_expr(%AST.Call{function: fun, args: args}, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(fun, scope, file, source_lines, errors)

    Enum.reduce(args, {scope, errors}, fn arg, {scope, errors} ->
      resolve_expr(arg, scope, file, source_lines, errors)
    end)
  end

  defp resolve_expr(%AST.MethodCall{receiver: recv, args: args}, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(recv, scope, file, source_lines, errors)

    Enum.reduce(args, {scope, errors}, fn arg, {scope, errors} ->
      resolve_expr(arg, scope, file, source_lines, errors)
    end)
  end

  defp resolve_expr(%AST.If{condition: cond_expr, then_branch: then_b, else_branch: else_b}, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(cond_expr, scope, file, source_lines, errors)
    {scope, errors} = resolve_body(then_b, scope, file, source_lines, errors)

    if else_b do
      resolve_body(else_b, scope, file, source_lines, errors)
    else
      {scope, errors}
    end
  end

  defp resolve_expr(%AST.When{subject: subj, branches: branches}, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(subj, scope, file, source_lines, errors)

    Enum.reduce(branches, {scope, errors}, fn branch, {scope, errors} ->
      resolve_when_branch(branch, scope, file, source_lines, errors)
    end)
  end

  defp resolve_expr(%AST.Lambda{params: params, body: body}, scope, file, source_lines, errors) do
    lambda_scope = push_scope(scope)

    lambda_scope =
      cond do
        is_list(params) and params != [] ->
          Enum.reduce(params, lambda_scope, fn name, scope ->
            put_var(scope, name, :val)
          end)

        true ->
          # implicit `it`
          put_var(lambda_scope, "it", :val)
      end

    Enum.reduce(body, {lambda_scope, errors}, fn stmt, {scope, errors} ->
      resolve_statement(stmt, scope, file, source_lines, errors)
    end)
  end

  defp resolve_expr(%AST.Block{statements: stmts}, scope, file, source_lines, errors) do
    block_scope = push_scope(scope)

    Enum.reduce(stmts, {block_scope, errors}, fn stmt, {scope, errors} ->
      resolve_statement(stmt, scope, file, source_lines, errors)
    end)
  end

  defp resolve_expr(%AST.FieldAccess{receiver: recv}, scope, file, source_lines, errors) do
    resolve_expr(recv, scope, file, source_lines, errors)
  end

  defp resolve_expr(%AST.SafeAccess{receiver: recv}, scope, file, source_lines, errors) do
    resolve_expr(recv, scope, file, source_lines, errors)
  end

  defp resolve_expr(%AST.Elvis{left: left, right: right}, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(left, scope, file, source_lines, errors)
    resolve_expr(right, scope, file, source_lines, errors)
  end

  defp resolve_expr(%AST.NotNull{expr: expr}, scope, file, source_lines, errors) do
    resolve_expr(expr, scope, file, source_lines, errors)
  end

  defp resolve_expr(%AST.ConstructorCall{args: args}, scope, file, source_lines, errors) do
    Enum.reduce(args, {scope, errors}, fn arg, {scope, errors} ->
      resolve_expr(arg, scope, file, source_lines, errors)
    end)
  end

  defp resolve_expr(%AST.StringInterp{parts: parts}, scope, file, source_lines, errors) do
    Enum.reduce(parts, {scope, errors}, fn
      {:expr, expr}, {scope, errors} ->
        resolve_expr(expr, scope, file, source_lines, errors)

      _, {scope, errors} ->
        {scope, errors}
    end)
  end

  defp resolve_expr(%AST.For{var: var_name, iterable: iter, body: body}, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(iter, scope, file, source_lines, errors)
    for_scope = push_scope(scope)
    for_scope = put_var(for_scope, var_name, :val)
    {_scope, errors} = resolve_body(body, for_scope, file, source_lines, errors)
    {scope, errors}
  end

  defp resolve_expr(%AST.Spawn{body: body}, scope, file, source_lines, errors) do
    resolve_body(body, scope, file, source_lines, errors)
  end

  defp resolve_expr(%AST.Receive{branches: branches}, scope, file, source_lines, errors) do
    Enum.reduce(branches, {scope, errors}, fn branch, {scope, errors} ->
      resolve_when_branch(branch, scope, file, source_lines, errors)
    end)
  end

  defp resolve_expr(%AST.Return{value: value}, scope, file, source_lines, errors) do
    if value do
      resolve_expr(value, scope, file, source_lines, errors)
    else
      {scope, errors}
    end
  end

  defp resolve_expr(%AST.Range{from: from, to: to}, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(from, scope, file, source_lines, errors)
    resolve_expr(to, scope, file, source_lines, errors)
  end

  defp resolve_expr(%AST.ListLit{elements: elems}, scope, file, source_lines, errors) do
    Enum.reduce(elems, {scope, errors}, fn elem, {scope, errors} ->
      resolve_expr(elem, scope, file, source_lines, errors)
    end)
  end

  defp resolve_expr(%AST.MapLit{entries: entries}, scope, file, source_lines, errors) do
    Enum.reduce(entries, {scope, errors}, fn {k, v}, {scope, errors} ->
      {scope, errors} = resolve_expr(k, scope, file, source_lines, errors)
      resolve_expr(v, scope, file, source_lines, errors)
    end)
  end

  defp resolve_expr(%AST.PairLit{first: a, second: b}, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(a, scope, file, source_lines, errors)
    resolve_expr(b, scope, file, source_lines, errors)
  end

  defp resolve_expr(%AST.InOp{element: elem, collection: coll}, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(elem, scope, file, source_lines, errors)
    resolve_expr(coll, scope, file, source_lines, errors)
  end

  defp resolve_expr(%AST.CopyCall{receiver: recv, updates: updates}, scope, file, source_lines, errors) do
    {scope, errors} = resolve_expr(recv, scope, file, source_lines, errors)

    Enum.reduce(updates, {scope, errors}, fn {_name, val}, {scope, errors} ->
      resolve_expr(val, scope, file, source_lines, errors)
    end)
  end

  # Terminals — no resolution needed
  defp resolve_expr(%AST.Literal{}, scope, _file, _source_lines, errors), do: {scope, errors}
  defp resolve_expr(nil, scope, _file, _source_lines, errors), do: {scope, errors}

  defp resolve_expr(_other, scope, _file, _source_lines, errors) do
    {scope, errors}
  end

  defp resolve_when_branch(%AST.WhenBranch{pattern: pattern, body: body}, scope, file, source_lines, errors) do
    branch_scope = push_scope(scope)

    # Add bindings from pattern
    branch_scope =
      case pattern do
        %AST.PatternIs{bindings: bindings} when is_list(bindings) and bindings != [] ->
          Enum.reduce(bindings, branch_scope, fn name, scope ->
            put_var(scope, name, :val)
          end)

        _ ->
          put_var(branch_scope, "it", :val)
      end

    {_scope, errors} = resolve_body(body, branch_scope, file, source_lines, errors)
    {scope, errors}
  end

  # ── Scope helpers ──────────────────────────────────────────────────

  defp push_scope(parent), do: %{vars: %{}, parent: parent}

  defp put_var(scope, name, kind), do: %{scope | vars: Map.put(scope.vars, name, kind)}

  defp get_var(%{vars: vars, parent: parent}, name) do
    case Map.get(vars, name) do
      nil when parent != nil -> get_var(parent, name)
      result -> result
    end
  end

  defp get_var_local(%{vars: vars}, name), do: Map.get(vars, name)

  defp builtin?(name) do
    name in ~w(println print readLine listOf mapOf self toString)
  end

  defp make_error(file, meta, message, source_lines) do
    line = Map.get(meta, :line, 1)
    col = Map.get(meta, :col, 1)
    source_line = Enum.at(source_lines, line - 1)
    Errors.new(file, line, col, message, source_line)
  end

  defp check_file_module_name(%AST.Module{name: mod_name, meta: meta}, file, source_lines) do
    if file != "nofile" and String.ends_with?(file, ".kore") do
      file_base = Path.basename(file, ".kore")
      expected_base = Kore.Prelude.to_snake_case(mod_name)

      if file_base != expected_base do
        line = Map.get(meta, :line, 1)
        col = Map.get(meta, :col, 1)
        source_line = Enum.at(source_lines, line - 1)

        [
          Errors.new(
            file,
            line,
            col,
            "file name '#{Path.basename(file)}' does not match module name '#{mod_name}' (expected '#{expected_base}.kore')",
            source_line
          )
        ]
      else
        []
      end
    else
      []
    end
  end

  defp check_early_returns(%AST.Block{statements: stmts}, file, source_lines) do
    if stmts == [] do
      []
    else
      {init_stmts, _last} = Enum.split(stmts, max(0, length(stmts) - 1))
      Enum.flat_map(init_stmts, &find_returns(&1, file, source_lines))
    end
  end

  defp check_early_returns(expr, file, source_lines) when not is_nil(expr) do
    find_returns(expr, file, source_lines)
  end

  defp check_early_returns(nil, _file, _source_lines), do: []

  defp find_returns(%AST.Return{meta: meta}, file, source_lines) do
    line = Map.get(meta, :line, 1)
    col = Map.get(meta, :col, 1)
    source_line = Enum.at(source_lines, line - 1)
    [Errors.new(file, line, col, "early return not supported; restructure using if/when expressions or move the return to the last position in the function body", source_line)]
  end

  defp find_returns(%AST.Block{statements: stmts}, file, source_lines) do
    Enum.flat_map(stmts, &find_returns(&1, file, source_lines))
  end

  defp find_returns(%AST.If{condition: c, then_branch: t, else_branch: e}, file, source_lines) do
    find_returns(c, file, source_lines) ++
      find_returns(t, file, source_lines) ++
      if(e, do: find_returns(e, file, source_lines), else: [])
  end

  defp find_returns(%AST.When{subject: s, branches: b}, file, source_lines) do
    find_returns(s, file, source_lines) ++
      Enum.flat_map(b, fn %AST.WhenBranch{body: body} -> find_returns(body, file, source_lines) end)
  end

  defp find_returns(%AST.ValDecl{value: v}, file, source_lines), do: find_returns(v, file, source_lines)
  defp find_returns(%AST.Assign{value: v}, file, source_lines), do: find_returns(v, file, source_lines)
  defp find_returns(%AST.Call{args: args}, file, source_lines), do: Enum.flat_map(args, &find_returns(&1, file, source_lines))
  defp find_returns(%AST.MethodCall{receiver: r, args: args}, file, source_lines) do
    find_returns(r, file, source_lines) ++ Enum.flat_map(args, &find_returns(&1, file, source_lines))
  end
  defp find_returns(_other, _file, _source_lines), do: []
end
