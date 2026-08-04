defmodule Kore.Parser do
  @moduledoc """
  Recursive descent parser with Pratt expression parsing for KorE.

  Transforms a token stream from `Kore.Lexer` into a KorE AST (`Kore.AST.File`).
  Handles all language constructs: modules, functions, data records, sealed types,
  actors, control flow, pattern matching, lambdas, and string interpolation.

  Returns `{:ok, AST.File.t()}` or `{:error, [Kore.Errors.t()]}`.
  """

  alias Kore.AST
  alias Kore.Errors

  @type token :: {atom(), term(), integer(), integer()}
  @type parse_result :: {:ok, AST.File.t()} | {:error, [{String.t(), integer(), integer()}]}

  def parse(tokens, file, source_lines) do
    state = %{
      tokens: tokens,
      errors: [],
      current: 0,
      file: file,
      source_lines: source_lines
    }

    try do
      {ast, state} = parse_file(state)
      if state.errors == [] do
        {:ok, ast}
      else
        {:error, Enum.reverse(state.errors)}
      end
    catch
      :error, %{message: msg, meta: meta} ->
        src_line = Enum.at(source_lines, max(meta.line - 1, 0))
        error = Errors.new(file, meta.line, meta.col, msg, src_line)
        {:error, [error | state.errors]}
    end
  end

  # Helpers
  defp peek(%{tokens: tokens, current: current} = _state) do
    if current < length(tokens) do
      Enum.at(tokens, current)
    else
      {:eof, nil, 0, 0}
    end
  end

  defp peek_type(state) do
    {type, _, _, _} = peek(state)
    type
  end

  defp consume(state) do
    tok = peek(state)
    {tok, %{state | current: state.current + 1}}
  end

  
  defp expect_identifier(state) do
    {type, _value, line, col} = peek(state)
    if type in [:identifier, :data, :in] do
      {tok, state} = consume(state)
      {{:identifier, to_string(elem(tok, 1)), elem(tok, 2), elem(tok, 3)}, state}
    else
      error(state, "Expected identifier, got #{token_display(type)}", %{line: line, col: col})
    end
  end

  defp expect(state, expected_type) do
    {type, _value, line, col} = peek(state)
    if type == expected_type do
      consume(state)
    else
      error(state, "Expected #{token_display(expected_type)}, got #{token_display(type)}", %{line: line, col: col})
    end
  end

  defp match(state, expected_type) do
    if peek_type(state) == expected_type do
      {_, new_state} = consume(state)
      {true, new_state}
    else
      {false, state}
    end
  end

  defp error(_state, msg, meta) do
    throw(%{message: msg, meta: meta})
  end

  defp token_display(type) do
    case type do
      :lparen -> "'('"
      :rparen -> "')'"
      :lbrace -> "'{'"
      :rbrace -> "'}'"
      :comma -> "','"
      :colon -> "':'"
      :semicolon -> "';'"
      :dot -> "'.'"
      :equal -> "'='"
      :arrow -> "'->'"
      :plus -> "'+'"
      :minus -> "'-'"
      :star -> "'*'"
      :slash -> "'/'"
      :percent -> "'%'"
      :less -> "'<'"
      :greater -> "'>'"
      :safe_dot -> "'?.'"
      :not_null -> "'!!'"
      :elvis -> "'?:'"
      :range -> "'..'"
      :plus_eq -> "'+='"
      :minus_eq -> "'-='"
      :identifier -> "identifier"
      :type_identifier -> "type name"
      :integer -> "integer literal"
      :int -> "integer literal"
      :double -> "float literal"
      :string -> "string literal"
      :newline -> "newline"
      :eof -> "end of file"
      other -> "'#{other}'"
    end
  end

  defp get_meta(state) do
    {_, _, line, col} = peek(state)
    %{line: line, col: col}
  end

  defp skip_newlines(state) do
    case peek_type(state) do
      :newline ->
        {_, state} = consume(state)
        skip_newlines(state)
      :semicolon ->
        {_, state} = consume(state)
        skip_newlines(state)
      _ ->
        state
    end
  end

  # Parsers
  defp parse_file(state) do
    state = skip_newlines(state)
    meta = get_meta(state)
    {imports, state} = parse_imports(state, [])
    state = skip_newlines(state)
    {module, state} = parse_module(state)
    {%AST.File{imports: imports, module: module, meta: meta}, state}
  end

  defp parse_imports(state, acc) do
    state = skip_newlines(state)
    if peek_type(state) == :import do
      {_, state} = consume(state)
      {_elixir_tok, state} = expect(state, :identifier) # expect 'elixir'
      {_, state} = expect(state, :dot)
      {path, state} = parse_dotted_name(state, [])
      
      import_node = %AST.Import{path: ["elixir" | path], meta: get_meta(state)}
      parse_imports(state, [import_node | acc])
    else
      {Enum.reverse(acc), state}
    end
  end

  defp parse_dotted_name(state, acc) do
    {tok, state} = expect(state, :type_identifier) # Or identifier? Usually types are uppercase.
    path = [elem(tok, 1) | acc]
    {has_dot, state} = match(state, :dot)
    if has_dot do
      parse_dotted_name(state, path)
    else
      {Enum.reverse(path), state}
    end
  end

  defp parse_module(state) do
    meta = get_meta(state)
    {_, state} = expect(state, :module)
    {{_, name, _, _}, state} = expect(state, :type_identifier)
    {_, state} = expect(state, :lbrace)
    {decls, state} = parse_declarations(state, [])
    {_, state} = expect(state, :rbrace)
    {%AST.Module{name: name, declarations: decls, meta: meta}, state}
  end

  defp parse_declarations(state, acc) do
    state = skip_newlines(state)
    if peek_type(state) in [:rbrace, :eof] do
      {Enum.reverse(acc), state}
    else
      {decl, state} = parse_declaration(state)
      state = skip_newlines(state)
      parse_declarations(state, [decl | acc])
    end
  end

  defp parse_declaration(state) do
    case peek_type(state) do
      :fun -> parse_fun_decl(state)
      :val -> parse_val_decl(state)
      :var -> parse_val_decl(state)
      :data -> parse_data_decl(state)
      :sealed -> parse_sealed_decl(state)
      :actor -> parse_actor_decl(state)
      _ ->
        {type, _, _, _} = peek(state)
        error(state, "Unexpected #{token_display(type)} at module level; expected 'fun', 'val', 'var', 'data', 'sealed', or 'actor'", get_meta(state))
    end
  end

  defp parse_fun_decl(state) do
    meta = get_meta(state)
    {_, state} = expect(state, :fun)
    {{_, name, _, _}, state} = expect_identifier(state)
    {_, state} = expect(state, :lparen)
    {params, state} = parse_params(state)
    {_, state} = expect(state, :rparen)
    
    {has_colon, state} = match(state, :colon)
    {return_type, state} = if has_colon do
      parse_type(state)
    else
      {nil, state}
    end

    {body, state} = case peek_type(state) do
      :lbrace -> parse_block(state)
      :equal -> 
        {_, state} = consume(state)
        parse_expr(state, 0)
      _ -> error(state, "Expected block or = for function body", get_meta(state))
    end

    {%AST.FunDecl{name: name, params: params, return_type: return_type, body: body, meta: meta}, state}
  end

  defp parse_params(state) do
    state = skip_newlines(state)
    if peek_type(state) == :rparen do
      {[], state}
    else
      parse_param_list(state, [])
    end
  end

  defp parse_param_list(state, acc) do
    state = skip_newlines(state)
    meta = get_meta(state)
    {{_, name, _, _}, state} = expect_identifier(state)
    {_, state} = expect(state, :colon)
    {type, state} = parse_type(state)
    
    {has_eq, state} = match(state, :equal)
    {default, state} = if has_eq do
      parse_expr(state, 0)
    else
      {nil, state}
    end

    param = %AST.Param{name: name, type: type, default: default, meta: meta}
    acc = [param | acc]

    {has_comma, state} = match(state, :comma)
    if has_comma do
      parse_param_list(state, acc)
    else
      {Enum.reverse(acc), state}
    end
  end

  defp parse_val_decl(state) do
    meta = get_meta(state)
    {tok, state} = consume(state)
    mutable = elem(tok, 0) == :var
    {{_, name, _, _}, state} = expect_identifier(state)

    {has_colon, state} = match(state, :colon)
    {type, state} = if has_colon do
      parse_type(state)
    else
      {nil, state}
    end

    {_, state} = expect(state, :equal)
    {value, state} = parse_expr(state, 0)

    {%AST.ValDecl{name: name, type: type, value: value, mutable: mutable, meta: meta}, state}
  end

  defp parse_data_decl(state) do
    meta = get_meta(state)
    {_, state} = expect(state, :data)
    {{_, name, _, _}, state} = expect(state, :type_identifier)
    {_, state} = expect(state, :lparen)
    {fields, state} = parse_data_fields(state)
    state = skip_newlines(state)
    {_, state} = expect(state, :rparen)
    {%AST.DataDecl{name: name, fields: fields, meta: meta}, state}
  end

  defp parse_data_fields(state) do
    state = skip_newlines(state)
    if peek_type(state) == :rparen do
      {[], state}
    else
      parse_data_field_list(state, [])
    end
  end

  defp parse_data_field_list(state, acc) do
    state = skip_newlines(state)
    meta = get_meta(state)
    {_, state} = expect(state, :val)
    {{_, name, _, _}, state} = expect_identifier(state)
    {_, state} = expect(state, :colon)
    {type, state} = parse_type(state)
    
    {has_eq, state} = match(state, :equal)
    {default, state} = if has_eq do
      parse_expr(state, 0)
    else
      {nil, state}
    end

    field = %AST.DataField{name: name, type: type, default: default, meta: meta}
    acc = [field | acc]

    {has_comma, state} = match(state, :comma)
    if has_comma do
      parse_data_field_list(state, acc)
    else
      {Enum.reverse(acc), state}
    end
  end

  defp parse_sealed_decl(state) do
    meta = get_meta(state)
    {_, state} = expect(state, :sealed)
    {{_, name, _, _}, state} = expect(state, :type_identifier)
    {_, state} = expect(state, :lbrace)
    {variants, state} = parse_variants(state, [])
    {_, state} = expect(state, :rbrace)
    {%AST.SealedDecl{name: name, variants: variants, meta: meta}, state}
  end

  defp parse_variants(state, acc) do
    state = skip_newlines(state)
    if peek_type(state) in [:rbrace, :eof] do
      {Enum.reverse(acc), state}
    else
      {decl, state} = parse_data_decl(state)
      state = skip_newlines(state)
      parse_variants(state, [decl | acc])
    end
  end

  defp parse_actor_decl(state) do
    meta = get_meta(state)
    {_, state} = expect(state, :actor)
    {{_, name, _, _}, state} = expect(state, :type_identifier)
    {_, state} = expect(state, :lparen)
    {fields, state} = parse_actor_fields(state)
    state = skip_newlines(state)
    {_, state} = expect(state, :rparen)
    state = skip_newlines(state)
    {_, state} = expect(state, :lbrace)
    {methods, state} = parse_actor_methods(state, [])
    state = skip_newlines(state)
    {_, state} = expect(state, :rbrace)
    
    {%AST.ActorDecl{name: name, fields: fields, methods: methods, meta: meta}, state}
  end

  defp parse_actor_fields(state) do
    state = skip_newlines(state)
    if peek_type(state) == :rparen do
      {[], state}
    else
      parse_actor_field_list(state, [])
    end
  end

  defp parse_actor_field_list(state, acc) do
    state = skip_newlines(state)
    meta = get_meta(state)
    tok = peek_type(state)
    {mutable, state} = if tok == :var do
      {_, state} = consume(state)
      {true, state}
    else
      {_, state} = expect(state, :val)
      {false, state}
    end

    {{_, name, _, _}, state} = expect_identifier(state)
    {_, state} = expect(state, :colon)
    {type, state} = parse_type(state)
    
    {has_eq, state} = match(state, :equal)
    {default, state} = if has_eq do
      parse_expr(state, 0)
    else
      {nil, state}
    end

    field = %AST.ActorField{name: name, type: type, default: default, mutable: mutable, meta: meta}
    acc = [field | acc]

    {has_comma, state} = match(state, :comma)
    if has_comma do
      parse_actor_field_list(state, acc)
    else
      {Enum.reverse(acc), state}
    end
  end

  defp parse_actor_methods(state, acc) do
    state = skip_newlines(state)
    if peek_type(state) in [:rbrace, :eof] do
      {Enum.reverse(acc), state}
    else
      {fun, state} = parse_fun_decl(state)
      state = skip_newlines(state)
      parse_actor_methods(state, [fun | acc])
    end
  end

  defp parse_block(state) do
    meta = get_meta(state)
    {_, state} = expect(state, :lbrace)
    {stmts, state} = parse_statements(state, [])
    state = skip_newlines(state)
    {_, state} = expect(state, :rbrace)
    {%AST.Block{statements: stmts, meta: meta}, state}
  end

  defp parse_statements(state, acc) do
    state = skip_newlines(state)
    if peek_type(state) in [:rbrace, :eof] do
      {Enum.reverse(acc), state}
    else
      {stmt, state} = parse_statement(state)
      
      # Optional semicolon
      {_, state} = match(state, :semicolon)
      state = skip_newlines(state)

      parse_statements(state, [stmt | acc])
    end
  end

  defp parse_statement(state) do
    case peek_type(state) do
      :val -> parse_val_decl(state)
      :var -> parse_val_decl(state)
      :return ->
        meta = get_meta(state)
        {_, state} = consume(state)
        if peek_type(state) in [:rbrace, :semicolon, :newline] do
          {%AST.Return{value: nil, meta: meta}, state}
        else
          {expr, state} = parse_expr(state, 0)
          {%AST.Return{value: expr, meta: meta}, state}
        end
      t when t in [:identifier, :data, :in] ->
        # Could be assignment, compound assignment, or expr
        next_tok = if state.current + 1 < length(state.tokens) do
          Enum.at(state.tokens, state.current + 1)
        else
          nil
        end
        next_type = if next_tok, do: elem(next_tok, 0), else: nil
        cond do
          next_type == :equal ->
            meta = get_meta(state)
            {{_, name, _, _}, state} = expect_identifier(state)
            {_, state} = expect(state, :equal)
            {value, state} = parse_expr(state, 0)
            {%AST.Assign{name: name, value: value, meta: meta}, state}
          next_type in [:plus_eq, :minus_eq] ->
            meta = get_meta(state)
            {{_, name, _, _}, state} = expect_identifier(state)
            {_, state} = consume(state)
            {rhs, state} = parse_expr(state, 0)
            op = if next_type == :plus_eq, do: :plus, else: :minus
            value = %AST.BinOp{op: op, left: %AST.VarRef{name: name, meta: meta}, right: rhs, meta: meta}
            {%AST.Assign{name: name, value: value, meta: meta}, state}
          true ->
            parse_expr(state, 0)
        end
      _ -> parse_expr(state, 0)
    end
  end

  # Expressions
  defp parse_expr(state, min_bp) do
    state = skip_newlines(state)
    {lhs, state} = parse_prefix(state)
    parse_infix(state, lhs, min_bp)
  end

  defp parse_prefix(state) do
    meta = get_meta(state)
    {type, value, _, _} = peek(state)
    
    case type do
      t when t in [:int, :integer] ->
        {_, state} = consume(state)
        {%AST.Literal{type: :int, value: value, meta: meta}, state}
      :double ->
        {_, state} = consume(state)
        {%AST.Literal{type: :double, value: value, meta: meta}, state}
      :string ->
        {_, state} = consume(state)
        {%AST.Literal{type: :string, value: value, meta: meta}, state}
      :true ->
        {_, state} = consume(state)
        {%AST.Literal{type: :bool, value: true, meta: meta}, state}
      :false ->
        {_, state} = consume(state)
        {%AST.Literal{type: :bool, value: false, meta: meta}, state}
      :boolean ->
        {_, state} = consume(state)
        {%AST.Literal{type: :bool, value: value, meta: meta}, state}
      :null ->
        {_, state} = consume(state)
        {%AST.Literal{type: :null, value: nil, meta: meta}, state}
      :atom ->
        {_, state} = consume(state)
        {%AST.Literal{type: :atom, value: value, meta: meta}, state}
      
      t when t in [:identifier, :data, :in] ->
        {tok, state} = consume(state)
        {%AST.VarRef{name: to_string(elem(tok, 1)), meta: meta}, state}
      
      :type_identifier ->
        {_, state} = consume(state)
        # Constructor call? If lparen is next. We handle constructor call in infix if type_ident is a prefix?
        # A type identifier by itself is an expr? E.g. in "is TypeName"
        # We can just emit it as VarRef or ConstructorRef for now.
        if peek_type(state) == :lparen do
          {_, state} = consume(state)
          {args, state} = parse_args(state)
          {_, state} = expect(state, :rparen)
          {%AST.ConstructorCall{type_name: value, args: args, meta: meta}, state}
        else
           {%AST.VarRef{name: value, meta: meta}, state} # Or error?
        end

      :if -> parse_if(state)
      :when -> parse_when(state)
      :for -> parse_for(state)
      :string_start -> parse_string_interp(state)
      :lbrace -> parse_lambda(state)
      :spawn ->
        {_, state} = consume(state)
        {body, state} = parse_lambda(state)
        {%AST.Spawn{body: body, meta: meta}, state}
      :receive ->
        {_, state} = consume(state)
        {_, state} = expect(state, :lbrace)
        {branches, state} = parse_when_branches(state, [])
        {_, state} = expect(state, :rbrace)
        {%AST.Receive{branches: branches, meta: meta}, state}

      :minus ->
        {_, state} = consume(state)
        {expr, state} = parse_expr(state, prefix_bp(:minus))
        {%AST.UnaryOp{op: :-, operand: expr, meta: meta}, state}
      :not ->
        {_, state} = consume(state)
        {expr, state} = parse_expr(state, prefix_bp(:not))
        {%AST.UnaryOp{op: :!, operand: expr, meta: meta}, state}
      
      :lparen ->
        {_, state} = consume(state)
        {expr, state} = parse_expr(state, 0)
        {_, state} = expect(state, :rparen)
        {expr, state}
      
      _ -> error(state, "Cannot start an expression with #{token_display(type)}; expected a value, identifier, '(', 'if', 'when', 'for', or unary operator", meta)
    end
  end

  defp parse_infix(state, lhs, min_bp) do
    meta = get_meta(state)
    {type, _, _, _} = peek(state)
    
    if type in [:dot, :safe_dot, :not_null, :lparen, :lbrace] or is_binary_op(type) do
      bp = infix_bp(type)
      
      if bp >= min_bp do # right associative means we could have > or >= but Pratt usually handles it by bp
        case type do
          :dot ->
            {_, state} = consume(state)
            next_type = peek_type(state)
            if next_type in [:identifier, :type_identifier] do
              {tok, state} = consume(state)
              name = elem(tok, 1)

              if next_type == :type_identifier do
                ref_name = case lhs do
                  %AST.VarRef{name: n} -> "#{n}.#{name}"
                  _ -> name
                end
                node = %AST.VarRef{name: ref_name, meta: meta}
                parse_infix(state, node, min_bp)
              else
                cond do
                  name == "copy" and peek_type(state) == :lparen ->
                    {_, state} = consume(state)
                    {updates, state} = parse_copy_updates(state, [])
                    {_, state} = expect(state, :rparen)
                    node = %AST.CopyCall{receiver: lhs, updates: updates, meta: meta}
                    parse_infix(state, node, min_bp)

                  peek_type(state) == :lparen ->
                    {_, state} = consume(state)
                    {args, state} = parse_args(state)
                    {_, state} = expect(state, :rparen)
                    
                    {trailing, state} = if peek_type(state) == :lbrace do
                      parse_lambda(state)
                    else
                      {nil, state}
                    end
                    
                    node = %AST.MethodCall{receiver: lhs, method: name, args: args, trailing_lambda: trailing, meta: meta}
                    parse_infix(state, node, min_bp)

                  peek_type(state) == :lbrace ->
                    {lambda, state} = parse_lambda(state)
                    node = %AST.MethodCall{receiver: lhs, method: name, args: [], trailing_lambda: lambda, meta: meta}
                    parse_infix(state, node, min_bp)

                  true ->
                    node = %AST.FieldAccess{receiver: lhs, field: name, meta: meta}
                    parse_infix(state, node, min_bp)
                end
              end
            else
              error(state, "Expected field or method name after '.', got #{token_display(next_type)}", get_meta(state))
            end

          :safe_dot ->
            {_, state} = consume(state)
            {{_, name, _, _}, state} = expect_identifier(state)
            node = %AST.SafeAccess{receiver: lhs, field: name, meta: meta}
            parse_infix(state, node, min_bp)

          :not_null ->
            {_, state} = consume(state)
            node = %AST.NotNull{expr: lhs, meta: meta}
            parse_infix(state, node, min_bp)
          
          :lparen ->
            # Call
            {_, state} = consume(state)
            {args, state} = parse_args(state)
            {_, state} = expect(state, :rparen)
            
            # Trailing lambda
            {trailing, state} = if peek_type(state) == :lbrace do
              parse_lambda(state)
            else
              {nil, state}
            end
            
            node = %AST.Call{function: lhs, args: args, trailing_lambda: trailing, meta: meta}
            parse_infix(state, node, min_bp)

          :lbrace ->
             # Trailing lambda on its own (like `foo { }`)
             # This is a bit tricky, but let's assume if it follows an expr and bp allows, it's a Call with trailing lambda
             {lambda, state} = parse_lambda(state)
             node = %AST.Call{function: lhs, args: [], trailing_lambda: lambda, meta: meta}
             parse_infix(state, node, min_bp)

          _ -> # Binary ops
             {_, state} = consume(state)
             {rhs, state} = parse_expr(state, bp + right_associative_offset(type))
             node = case type do
               :elvis -> %AST.Elvis{left: lhs, right: rhs, meta: meta}
               :to -> %AST.PairLit{first: lhs, second: rhs, meta: meta}
               :in -> %AST.InOp{element: lhs, collection: rhs, meta: meta}
               _ -> %AST.BinOp{op: type, left: lhs, right: rhs, meta: meta}
             end
             parse_infix(state, node, min_bp)
        end
      else
        {lhs, state}
      end
    else
      {lhs, state}
    end
  end

  defp is_binary_op(op) do
    op in [:plus, :minus, :star, :slash, :percent, :range, 
           :less, :greater, :less_eq, :greater_eq, :eq_eq, :not_eq,
           :and_and, :or_or, :elvis, :to, :in]
  end

  defp prefix_bp(:minus), do: 100
  defp prefix_bp(:not), do: 100
  
  defp infix_bp(:dot), do: 110
  defp infix_bp(:safe_dot), do: 110
  defp infix_bp(:not_null), do: 110
  defp infix_bp(:lparen), do: 110
  defp infix_bp(:lbrace), do: 10 # trailing lambda
  
  defp infix_bp(:star), do: 90
  defp infix_bp(:slash), do: 90
  defp infix_bp(:percent), do: 90
  
  defp infix_bp(:plus), do: 80
  defp infix_bp(:minus), do: 80
  
  defp infix_bp(:range), do: 70
  
  defp infix_bp(:less), do: 60
  defp infix_bp(:greater), do: 60
  defp infix_bp(:less_eq), do: 60
  defp infix_bp(:greater_eq), do: 60
  defp infix_bp(:in), do: 60
  defp infix_bp(:to), do: 55
  
  defp infix_bp(:eq_eq), do: 50
  defp infix_bp(:not_eq), do: 50
  
  defp infix_bp(:and_and), do: 40
  
  defp infix_bp(:or_or), do: 30
  
  defp infix_bp(:elvis), do: 20

  defp parse_for(state) do
    meta = get_meta(state)
    {_, state} = expect(state, :for)
    {_, state} = expect(state, :lparen)
    {{_, var_name, _, _}, state} = expect_identifier(state)
    {_, state} = expect(state, :in)
    {iterable, state} = parse_expr(state, 0)
    {_, state} = expect(state, :rparen)
    state = skip_newlines(state)
    {body, state} = if peek_type(state) == :lbrace do
      parse_block(state)
    else
      parse_expr(state, 0)
    end
    {%AST.For{var: var_name, iterable: iterable, body: body, meta: meta}, state}
  end
  
  defp right_associative_offset(_), do: 1 # For left associative it's 1

  defp parse_args(state) do
    if peek_type(state) == :rparen do
      {[], state}
    else
      parse_arg_list(state, [])
    end
  end

  defp parse_arg_list(state, acc) do
    {expr, state} = parse_expr(state, 0)
    acc = [expr | acc]
    {has_comma, state} = match(state, :comma)
    if has_comma do
      parse_arg_list(state, acc)
    else
      {Enum.reverse(acc), state}
    end
  end

  defp parse_copy_updates(state, acc) do
    if peek_type(state) == :rparen do
      {Enum.reverse(acc), state}
    else
      {{_, field_name, _, _}, state} = expect_identifier(state)
      {_, state} = expect(state, :equal)
      {val, state} = parse_expr(state, 0)
      acc = [{field_name, val} | acc]
      {has_comma, state} = match(state, :comma)
      if has_comma do
        parse_copy_updates(state, acc)
      else
        {Enum.reverse(acc), state}
      end
    end
  end

  defp parse_if(state) do
    meta = get_meta(state)
    {_, state} = expect(state, :if)
    {_, state} = expect(state, :lparen)
    {cond, state} = parse_expr(state, 0)
    {_, state} = expect(state, :rparen)

    {then_branch, state} =
      if peek_type(state) == :lbrace do
        parse_block(state)
      else
        parse_expr(state, 0)
      end

    state = skip_newlines(state)
    {has_else, state} = match(state, :else)

    {else_branch, state} =
      if has_else do
        state = skip_newlines(state)

        if peek_type(state) == :if do
          parse_if(state)
        else
          if peek_type(state) == :lbrace do
            parse_block(state)
          else
            parse_expr(state, 0)
          end
        end
      else
        {nil, state}
      end

    {%AST.If{condition: cond, then_branch: then_branch, else_branch: else_branch, meta: meta}, state}
  end

  defp parse_when(state) do
    meta = get_meta(state)
    {_, state} = expect(state, :when)
    {_, state} = expect(state, :lparen)
    {subject, state} = parse_expr(state, 0)
    {_, state} = expect(state, :rparen)
    {_, state} = expect(state, :lbrace)
    {branches, state} = parse_when_branches(state, [])
    {_, state} = expect(state, :rbrace)
    {%AST.When{subject: subject, branches: branches, meta: meta}, state}
  end

  defp parse_when_branches(state, acc) do
    state = skip_newlines(state)
    if peek_type(state) in [:rbrace, :eof] do
      {Enum.reverse(acc), state}
    else
      {branch, state} = parse_when_branch(state)
      state = skip_newlines(state)
      parse_when_branches(state, [branch | acc])
    end
  end

  defp parse_string_interp(state) do
    meta = get_meta(state)
    {_, state} = expect(state, :string_start)
    {parts, state} = parse_string_parts(state, [])
    {_, state} = expect(state, :string_end)
    {%AST.StringInterp{parts: parts, meta: meta}, state}
  end

  defp parse_string_parts(state, acc) do
    case peek_type(state) do
      :string_end ->
        {Enum.reverse(acc), state}

      :string_part ->
        {{_, val, _, _}, state} = consume(state)
        parse_string_parts(state, [{:string, val} | acc])

      :interp_start ->
        {_, state} = consume(state)
        {expr, state} = parse_expr(state, 0)
        state = skip_newlines(state)
        {_, state} = expect(state, :interp_end)
        parse_string_parts(state, [{:expr, expr} | acc])

      _ ->
        {Enum.reverse(acc), state}
    end
  end

  defp parse_when_branch(state) do
    meta = get_meta(state)
    
    # pattern
    {pattern, state} = case peek_type(state) do
      :is ->
        {_, state} = consume(state)
        {{_, type_name, _, _}, state} = expect(state, :type_identifier)
        {has_lparen, state} = match(state, :lparen)
        {bindings, state} = if has_lparen do
          {b, state} = parse_bind_list(state, [])
          {_, state} = expect(state, :rparen)
          {b, state}
        else
          {nil, state}
        end
        {%AST.PatternIs{type_name: type_name, bindings: bindings, meta: meta}, state}
      :else ->
        {_, state} = consume(state)
        {%AST.PatternElse{meta: meta}, state}
      _ ->
        # exprs
        {exprs, state} = parse_arg_list(state, [])
        {%AST.PatternValue{values: exprs, meta: meta}, state}
    end

    {_, state} = expect(state, :arrow) # ->
    
    {body, state} = if peek_type(state) == :lbrace do
      parse_block(state)
    else
      parse_expr(state, 0)
    end
    
    {%AST.WhenBranch{pattern: pattern, body: body, meta: meta}, state}
  end

  defp parse_bind_list(state, acc) do
    {_, state} = expect(state, :val)
    {{_, name, _, _}, state} = expect_identifier(state)
    acc = [name | acc]
    {has_comma, state} = match(state, :comma)
    if has_comma do
      parse_bind_list(state, acc)
    else
      {Enum.reverse(acc), state}
    end
  end

  defp parse_lambda(state) do
    meta = get_meta(state)
    {_, state} = expect(state, :lbrace)
    
    # check for arrow
    # since we don't have infinite lookahead, let's look for arrow in the next few tokens
    # Actually, we can just peek ahead until -> or } or newline to see if it's params.
    has_arrow = check_for_arrow(state.tokens, state.current)
    
    {params, state} = if has_arrow do
      {p, state} = parse_lambda_params(state, [])
      {_, state} = expect(state, :arrow)
      {p, state}
    else
      {nil, state}
    end

    {body, state} = parse_statements(state, [])
    {_, state} = expect(state, :rbrace)
    
    {%AST.Lambda{params: params, body: body, meta: meta}, state}
  end

  defp check_for_arrow(tokens, current) do
    case Enum.at(tokens, current) do
      nil -> false
      {:arrow, _, _, _} -> true
      {:rbrace, _, _, _} -> false
      {:identifier, _, _, _} -> check_for_arrow(tokens, current + 1)
      {:data, _, _, _} -> check_for_arrow(tokens, current + 1)
      {:in, _, _, _} -> check_for_arrow(tokens, current + 1)
      {:comma, _, _, _} -> check_for_arrow(tokens, current + 1)
      _ -> false
    end
  end

  defp parse_lambda_params(state, acc) do
    {{_, name, _, _}, state} = expect_identifier(state)
    acc = [name | acc]
    {has_comma, state} = match(state, :comma)
    if has_comma do
      parse_lambda_params(state, acc)
    else
      {Enum.reverse(acc), state}
    end
  end

  defp parse_dotted_type_name(state, acc) do
    {type_tok, _, _, _} = peek(state)
    {{_, name, _, _}, state} = 
      if type_tok in [:type_identifier, :identifier] do
        consume(state)
      else
        expect(state, :type_identifier)
      end
      
    path = [name | acc]
    {has_dot, state} = match(state, :dot)
    if has_dot do
      parse_dotted_type_name(state, path)
    else
      {Enum.reverse(path), state}
    end
  end

  defp parse_type(state) do
    meta = get_meta(state)
    {path, state} = parse_dotted_type_name(state, [])
    name = Enum.join(path, ".")
    
    {has_less, state} = match(state, :less)
    {params, state} = if has_less do
      {p, state} = parse_type_params(state, [])
      {_, state} = expect(state, :greater)
      {p, state}
    else
      {nil, state}
    end
    
    {has_q, state} = match(state, :question)
    {%AST.TypeRef{name: name, params: params, nullable: has_q, meta: meta}, state}
  end

  defp parse_type_params(state, acc) do
    {type, state} = parse_type(state)
    acc = [type | acc]
    {has_comma, state} = match(state, :comma)
    if has_comma do
      parse_type_params(state, acc)
    else
      {Enum.reverse(acc), state}
    end
  end

end
