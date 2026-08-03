defmodule Kore.Semantics.VarThreading do
  @moduledoc """
  Var threading rewrite pass (§7.4 / §6.4).

  Blocks (if/when used as statements) that rebind outer `var`s are rewritten
  so the new value escapes the block, since Elixir scoping discards inner bindings.

  Algorithm:
  1. For each if/when *statement* (not expression position), compute the set V
     of outer vars assigned in any branch.
  2. If V is empty, no rewrite.
  3. If |V| = 1: make the block evaluate to the final value of that var in each
     branch (append var as last expression; for absent else, synthesize else -> var),
     and bind: `var = if ... end`.
  4. If |V| > 1: evaluate to a tuple `{x, y}` per branch and destructure:
     `{x, y} = if ... end`.

  Applied bottom-up (nested blocks first).
  """

  alias Kore.AST

  @doc """
  Rewrite the AST with var threading applied.
  Returns `{:ok, rewritten_ast}`.
  """
  def rewrite(%AST.File{} = ast, _file, _source_lines) do
    module = rewrite_module(ast.module)
    {:ok, %{ast | module: module}}
  end

  defp rewrite_module(%AST.Module{declarations: decls} = mod) do
    decls = Enum.map(decls, &rewrite_declaration/1)
    %{mod | declarations: decls}
  end

  defp rewrite_declaration(%AST.FunDecl{body: body} = fun) do
    %{fun | body: rewrite_body(body, MapSet.new())}
  end

  defp rewrite_declaration(other), do: other

  defp rewrite_body(%AST.Block{statements: stmts} = block, outer_vars) do
    {new_stmts, _vars} = rewrite_statements(stmts, outer_vars)
    %{block | statements: new_stmts}
  end

  defp rewrite_body(expr, _outer_vars), do: expr

  defp rewrite_statements(stmts, outer_vars) do
    Enum.reduce(stmts, {[], outer_vars}, fn stmt, {acc, vars} ->
      case stmt do
        %AST.ValDecl{name: name, mutable: true} = decl ->
          decl = %{decl | value: rewrite_expr(decl.value)}
          {acc ++ [decl], MapSet.put(vars, name)}

        %AST.ValDecl{} = decl ->
          decl = %{decl | value: rewrite_expr(decl.value)}
          {acc ++ [decl], vars}

        %AST.If{} = if_node ->
          rewritten = thread_if(if_node, vars)
          case rewritten do
            stmts when is_list(stmts) -> {acc ++ stmts, vars}
            stmt -> {acc ++ [stmt], vars}
          end

        %AST.When{} = when_node ->
          rewritten = thread_when(when_node, vars)
          case rewritten do
            stmts when is_list(stmts) -> {acc ++ stmts, vars}
            stmt -> {acc ++ [stmt], vars}
          end

        %AST.Assign{} = assign ->
          assign = %{assign | value: rewrite_expr(assign.value)}
          {acc ++ [assign], vars}

        other ->
          {acc ++ [rewrite_expr(other)], vars}
      end
    end)
  end

  # ── If threading ───────────────────────────────────────────────────

  defp thread_if(%AST.If{} = if_node, outer_vars) do
    # First, recursively rewrite the branches
    then_branch = rewrite_body(if_node.then_branch, outer_vars)
    else_branch = if if_node.else_branch, do: rewrite_body(if_node.else_branch, outer_vars), else: nil

    # Find vars assigned in either branch
    then_assigned = find_assigned_vars(then_branch)
    else_assigned = if else_branch, do: find_assigned_vars(else_branch), else: MapSet.new()

    threaded_vars =
      MapSet.union(then_assigned, else_assigned)
      |> MapSet.intersection(outer_vars)

    if MapSet.size(threaded_vars) == 0 do
      %{if_node | then_branch: then_branch, else_branch: else_branch,
        condition: rewrite_expr(if_node.condition)}
    else
      vars_list = MapSet.to_list(threaded_vars) |> Enum.sort()

      # Add the var(s) as trailing expression in each branch
      then_branch = append_var_returns(then_branch, vars_list)

      else_branch =
        if else_branch do
          append_var_returns(else_branch, vars_list)
        else
          # Synthesize else branch that returns current var values
          make_var_return_block(vars_list, if_node.meta)
        end

      new_if = %{if_node |
        condition: rewrite_expr(if_node.condition),
        then_branch: then_branch,
        else_branch: else_branch
      }

      # Create the assignment(s)
      if length(vars_list) == 1 do
        [var_name] = vars_list
        [%AST.Assign{name: var_name, value: new_if, meta: if_node.meta}]
      else
        [%AST.TupleAssign{names: vars_list, value: new_if, meta: if_node.meta}]
      end
    end
  end

  # ── When threading ─────────────────────────────────────────────────

  defp thread_when(%AST.When{} = when_node, outer_vars) do
    branches = Enum.map(when_node.branches, fn branch ->
      %{branch | body: rewrite_body(branch.body, outer_vars)}
    end)

    all_assigned =
      Enum.reduce(branches, MapSet.new(), fn branch, acc ->
        MapSet.union(acc, find_assigned_vars(branch.body))
      end)

    threaded_vars = MapSet.intersection(all_assigned, outer_vars)

    if MapSet.size(threaded_vars) == 0 do
      %{when_node | branches: branches, subject: rewrite_expr(when_node.subject)}
    else
      vars_list = MapSet.to_list(threaded_vars) |> Enum.sort()

      branches = Enum.map(branches, fn branch ->
        %{branch | body: append_var_returns(branch.body, vars_list)}
      end)

      new_when = %{when_node |
        subject: rewrite_expr(when_node.subject),
        branches: branches
      }

      if length(vars_list) == 1 do
        [var_name] = vars_list
        [%AST.Assign{name: var_name, value: new_when, meta: when_node.meta}]
      else
        [%AST.TupleAssign{names: vars_list, value: new_when, meta: when_node.meta}]
      end
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp find_assigned_vars(%AST.Block{statements: stmts}) do
    Enum.reduce(stmts, MapSet.new(), fn
      %AST.Assign{name: name}, acc -> MapSet.put(acc, name)
      _, acc -> acc
    end)
  end

  defp find_assigned_vars(_), do: MapSet.new()

  defp append_var_returns(%AST.Block{statements: stmts} = block, [var_name]) do
    %{block | statements: stmts ++ [%AST.VarRef{name: var_name, meta: block.meta}]}
  end

  defp append_var_returns(%AST.Block{statements: stmts} = block, vars_list) do
    tuple = %AST.TupleLit{
      elements: Enum.map(vars_list, fn name -> %AST.VarRef{name: name, meta: block.meta} end),
      meta: block.meta
    }

    %{block | statements: stmts ++ [tuple]}
  end

  defp append_var_returns(expr, vars_list) do
    meta = if is_map(expr) and Map.has_key?(expr, :meta), do: expr.meta, else: %{line: 1, col: 1}

    ret_expr =
      if length(vars_list) == 1 do
        %AST.VarRef{name: hd(vars_list), meta: meta}
      else
        %AST.TupleLit{
          elements: Enum.map(vars_list, fn name -> %AST.VarRef{name: name, meta: meta} end),
          meta: meta
        }
      end

    %AST.Block{
      statements: [expr, ret_expr],
      meta: meta
    }
  end

  defp make_var_return_block([var_name], meta) do
    %AST.Block{
      statements: [%AST.VarRef{name: var_name, meta: meta}],
      meta: meta
    }
  end

  defp make_var_return_block(vars_list, meta) do
    %AST.Block{
      statements: [
        %AST.TupleLit{
          elements: Enum.map(vars_list, fn name -> %AST.VarRef{name: name, meta: meta} end),
          meta: meta
        }
      ],
      meta: meta
    }
  end

  defp rewrite_expr(%AST.BinOp{left: l, right: r} = node) do
    %{node | left: rewrite_expr(l), right: rewrite_expr(r)}
  end

  defp rewrite_expr(%AST.UnaryOp{operand: o} = node) do
    %{node | operand: rewrite_expr(o)}
  end

  defp rewrite_expr(%AST.Call{function: f, args: args} = node) do
    %{node | function: rewrite_expr(f), args: Enum.map(args, &rewrite_expr/1)}
  end

  defp rewrite_expr(%AST.MethodCall{receiver: r, args: args} = node) do
    %{node | receiver: rewrite_expr(r), args: Enum.map(args, &rewrite_expr/1)}
  end

  defp rewrite_expr(%AST.If{} = node) do
    %{node |
      condition: rewrite_expr(node.condition),
      then_branch: rewrite_body(node.then_branch, MapSet.new()),
      else_branch: if(node.else_branch, do: rewrite_body(node.else_branch, MapSet.new()))
    }
  end

  defp rewrite_expr(other), do: other
end
