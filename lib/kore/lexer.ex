defmodule Kore.Lexer do
  @moduledoc """
  Hand-written scanner for KorE.
  """

  @keywords ~w(module fun val var data sealed when is if else return import actor spawn receive true false null in for to)
  @ops2 ["?.", "!!", "..", "<=", ">=", "==", "!=", "&&", "||", "?:", "+=", "-=", "->"]
  @ops1 [".", "-", "!", "*", "/", "%", "+", "<", ">", "=", "(", ")", "{", "}", ",", ":", ";", "?"]

  # Map raw operator/punctuation strings to named token atoms
  @token_names %{
    # 2-char ops
    "?." => :safe_dot, "!!" => :not_null, ".." => :range,
    "<=" => :less_eq, ">=" => :greater_eq, "==" => :eq_eq, "!=" => :not_eq,
    "&&" => :and_and, "||" => :or_or, "?:" => :elvis,
    "+=" => :plus_eq, "-=" => :minus_eq, "->" => :arrow,
    # 1-char ops
    "." => :dot, "-" => :minus, "!" => :not, "*" => :star,
    "/" => :slash, "%" => :percent, "+" => :plus,
    "<" => :less, ">" => :greater, "=" => :equal,
    "(" => :lparen, ")" => :rparen, "{" => :lbrace, "}" => :rbrace,
    "," => :comma, ":" => :colon, ";" => :semicolon, "?" => :question
  }

  @spec tokenize(String.t(), String.t()) :: {:ok, [tuple()]} | {:error, [Kore.Errors.t()]}
  def tokenize(input, file \\ "nofile") do
    lines = String.split(input, ~r/\r\n|\n|\r/) |> List.to_tuple()
    do_tokenize(input, file, 1, 1, [], [], lines)
  end

  defp get_line(lines, line) do
    if line >= 1 and line <= tuple_size(lines) do
      elem(lines, line - 1)
    else
      ""
    end
  end

  # End of input
  defp do_tokenize("", _file, _line, _col, acc, [], _lines) do
    {:ok, Enum.reverse(acc)}
  end
  defp do_tokenize("", file, line, col, _acc, _mode, lines) do
    err = Kore.Errors.new(file, line, col, "Unexpected end of input", get_line(lines, line))
    {:error, [err]}
  end

  # Inside string mode
  defp do_tokenize(rest, file, line, col, acc, [:string | mode] = current_mode, lines) do
    case scan_string_part(rest, line, col, "") do
      {:ok, part, new_line, new_col, <<"\"", rem::binary>>} ->
        acc = if part != "", do: [{:string_part, part, line, col} | acc], else: acc
        do_tokenize(rem, file, new_line, new_col + 1, [{:string_end, :string_end, new_line, new_col} | acc], mode, lines)
      
      {:ok, part, new_line, new_col, <<"${", rem::binary>>} ->
        acc = if part != "", do: [{:string_part, part, line, col} | acc], else: acc
        acc = [{:interp_start, :interp_start, new_line, new_col} | acc]
        do_tokenize(rem, file, new_line, new_col + 2, acc, [{:interp, 1} | current_mode], lines)
        
      {:ok, part, new_line, new_col, <<"$", rem::binary>>} ->
        acc = if part != "", do: [{:string_part, part, line, col} | acc], else: acc
        acc = [{:interp_start, :interp_start, new_line, new_col} | acc]
        case Regex.run(~r/^[a-zA-Z_][a-zA-Z0-9_]*/, rem) do
          [id] ->
            rem_after_id = binary_part(rem, byte_size(id), byte_size(rem) - byte_size(id))
            acc = [{:identifier, id, new_line, new_col + 1} | acc]
            acc = [{:interp_end, :interp_end, new_line, new_col + 1 + byte_size(id)} | acc]
            do_tokenize(rem_after_id, file, new_line, new_col + 1 + byte_size(id), acc, current_mode, lines)
          nil ->
            err = Kore.Errors.new(file, new_line, new_col + 1, "Invalid interpolation identifier", get_line(lines, new_line))
            {:error, [err]}
        end
        
      {:error, msg, err_line, err_col} ->
        err = Kore.Errors.new(file, err_line, err_col, msg, get_line(lines, err_line))
        {:error, [err]}
    end
  end

  # Whitespace
  defp do_tokenize(<<char, rest::binary>>, file, line, col, acc, mode, lines) when char in [?\s, ?\t, ?\r] do
    do_tokenize(rest, file, line, col + 1, acc, mode, lines)
  end

  # Newline
  defp do_tokenize(<<"\n", rest::binary>>, file, line, col, acc, mode, lines) do
    acc = case acc do
      [{:newline, _, _, _} | _] -> acc
      _ -> [{:newline, :newline, line, col} | acc]
    end
    do_tokenize(rest, file, line + 1, 1, acc, mode, lines)
  end

  # Line comment
  defp do_tokenize(<<"//", rest::binary>>, file, line, col, acc, mode, lines) do
    case String.split(rest, "\n", parts: 2) do
      [comment] -> 
        do_tokenize("", file, line, col + 2 + byte_size(comment), acc, mode, lines)
      [comment, next_line_and_rest] ->
        do_tokenize("\n" <> next_line_and_rest, file, line, col + 2 + byte_size(comment), acc, mode, lines)
    end
  end

  # Block comment
  defp do_tokenize(<<"/*", rest::binary>>, file, line, col, acc, mode, lines) do
    case skip_block_comment(rest, line, col + 2) do
      {:ok, remaining, new_line, new_col} ->
        do_tokenize(remaining, file, new_line, new_col, acc, mode, lines)
      {:error, new_line, new_col} ->
        err = Kore.Errors.new(file, new_line, new_col, "Unterminated block comment", get_line(lines, new_line))
        {:error, [err]}
    end
  end

  # Atom literals
  defp do_tokenize(<<?:, char, rest::binary>>, file, line, col, acc, mode, lines) when char in ?a..?z or char in ?A..?Z or char == ?_ do
    {atom_name, remaining} = scan_identifier(<<char, rest::binary>>)
    do_tokenize(remaining, file, line, col + 1 + byte_size(atom_name), [{:atom, String.to_atom(atom_name), line, col} | acc], mode, lines)
  end

  # Number literals
  defp do_tokenize(<<char, _::binary>> = input, file, line, col, acc, mode, lines) when char in ?0..?9 do
    case scan_number(input) do
      {:ok, type, value, length, remaining} ->
        do_tokenize(remaining, file, line, col + length, [{type, value, line, col} | acc], mode, lines)
      {:error, msg, _length} ->
        err = Kore.Errors.new(file, line, col, msg, get_line(lines, line))
        {:error, [err]}
    end
  end

  # Strings
  defp do_tokenize(<<"\"", rest::binary>>, file, line, col, acc, mode, lines) do
    case scan_simple_string(rest, line, col + 1, "") do
      {:ok, str_val, new_line, new_col, remaining} ->
        do_tokenize(remaining, file, new_line, new_col, [{:string, str_val, line, col} | acc], mode, lines)
      :interpolation ->
        do_tokenize(rest, file, line, col + 1, [{:string_start, :string_start, line, col} | acc], [:string | mode], lines)
      {:error, msg, err_line, err_col} ->
        err = Kore.Errors.new(file, err_line, err_col, msg, get_line(lines, err_line))
        {:error, [err]}
    end
  end

  # 2-character ops
  defp do_tokenize(<<op::binary-size(2), rest::binary>>, file, line, col, acc, mode, lines) when op in @ops2 do
    tok_name = Map.get(@token_names, op, String.to_atom(op))
    do_tokenize(rest, file, line, col + 2, [{tok_name, tok_name, line, col} | acc], mode, lines)
  end

  # 1-character ops and punctuation
  defp do_tokenize(<<op::binary-size(1), rest::binary>>, file, line, col, acc, mode, lines) when op in @ops1 do
    tok_name = Map.get(@token_names, op, String.to_atom(op))
    acc_new = [{tok_name, tok_name, line, col} | acc]
    {new_mode, acc_new_2} = update_mode_for_brace(op, mode, acc_new, line, col)
    do_tokenize(rest, file, line, col + 1, acc_new_2, new_mode, lines)
  end

  # Identifiers and keywords
  defp do_tokenize(<<char, _::binary>> = input, file, line, col, acc, mode, lines) when char in ?a..?z or char in ?A..?Z or char == ?_ do
    {id_str, remaining} = scan_identifier(input)
    token = if id_str in @keywords do
      {String.to_atom(id_str), String.to_atom(id_str), line, col}
    else
      if String.at(id_str, 0) =~ ~r/^[A-Z]/ do
        {:type_identifier, id_str, line, col}
      else
        {:identifier, id_str, line, col}
      end
    end
    do_tokenize(remaining, file, line, col + byte_size(id_str), [token | acc], mode, lines)
  end

  # Catch-all
  defp do_tokenize(<<_char::utf8, _rest::binary>>, file, line, col, _acc, _mode, lines) do
    err = Kore.Errors.new(file, line, col, "Invalid character", get_line(lines, line))
    {:error, [err]}
  end

  # Helpers
  
  defp update_mode_for_brace("{", [{:interp, level} | rest_mode], acc, _line, _col) do
    {[{:interp, level + 1} | rest_mode], acc}
  end
  defp update_mode_for_brace("}", [{:interp, 1}, :string | rest_mode], acc, line, col) do
    {[:string | rest_mode], [{:interp_end, :interp_end, line, col} | tl(acc)]}
  end
  defp update_mode_for_brace("}", [{:interp, level} | rest_mode], acc, _line, _col) do
    {[{:interp, level - 1} | rest_mode], acc}
  end
  defp update_mode_for_brace(_op, mode, acc, _line, _col), do: {mode, acc}

  defp skip_block_comment(<<"*/", rest::binary>>, line, col) do
    {:ok, rest, line, col + 2}
  end
  defp skip_block_comment(<<"\n", rest::binary>>, line, _col) do
    skip_block_comment(rest, line + 1, 1)
  end
  defp skip_block_comment(<<_, rest::binary>>, line, col) do
    skip_block_comment(rest, line, col + 1)
  end
  defp skip_block_comment("", line, col) do
    {:error, line, col}
  end

  defp scan_identifier(input) do
    [match] = Regex.run(~r/^[a-zA-Z_][a-zA-Z0-9_]*/, input)
    {match, binary_part(input, byte_size(match), byte_size(input) - byte_size(match))}
  end

  defp scan_number(input) do
    case Regex.run(~r/^\d[\d_]*\.\d[\d_]*/, input) do
      [match] ->
        clean = String.replace(match, "_", "")
        {:ok, :double, String.to_float(clean), byte_size(match), binary_part(input, byte_size(match), byte_size(input) - byte_size(match))}
      nil ->
        case Regex.run(~r/^\d[\d_]*/, input) do
          [match] ->
            clean = String.replace(match, "_", "")
            {:ok, :integer, String.to_integer(clean), byte_size(match), binary_part(input, byte_size(match), byte_size(input) - byte_size(match))}
          nil ->
            {:error, "Invalid number", 1}
        end
    end
  end

  defp scan_simple_string(<<"\"", rest::binary>>, line, col, acc) do
    {:ok, acc, line, col + 1, rest}
  end
  defp scan_simple_string(<<"\\\"", rest::binary>>, line, col, acc) do
    scan_simple_string(rest, line, col + 2, acc <> "\"")
  end
  defp scan_simple_string(<<"\\\\", rest::binary>>, line, col, acc) do
    scan_simple_string(rest, line, col + 2, acc <> "\\")
  end
  defp scan_simple_string(<<"\\n", rest::binary>>, line, col, acc) do
    scan_simple_string(rest, line, col + 2, acc <> "\n")
  end
  defp scan_simple_string(<<"\\t", rest::binary>>, line, col, acc) do
    scan_simple_string(rest, line, col + 2, acc <> "\t")
  end
  defp scan_simple_string(<<"\\r", rest::binary>>, line, col, acc) do
    scan_simple_string(rest, line, col + 2, acc <> "\r")
  end
  defp scan_simple_string(<<"$", _rest::binary>>, _line, _col, _acc) do
    :interpolation
  end
  defp scan_simple_string(<<"\n", rest::binary>>, line, _col, acc) do
    scan_simple_string(rest, line + 1, 1, acc <> "\n")
  end
  defp scan_simple_string(<<char::utf8, rest::binary>>, line, col, acc) do
    scan_simple_string(rest, line, col + 1, acc <> <<char::utf8>>)
  end
  defp scan_simple_string("", line, col, _acc) do
    {:error, "Unterminated string", line, col}
  end

  defp scan_string_part(<<"\"", _rest::binary>> = input, line, col, acc) do
    {:ok, acc, line, col, input}
  end
  defp scan_string_part(<<"${", _rest::binary>> = input, line, col, acc) do
    {:ok, acc, line, col, input}
  end
  defp scan_string_part(<<"$", _rest::binary>> = input, line, col, acc) do
    {:ok, acc, line, col, input}
  end
  defp scan_string_part(<<"\\\"", rest::binary>>, line, col, acc) do
    scan_string_part(rest, line, col + 2, acc <> "\"")
  end
  defp scan_string_part(<<"\\\\", rest::binary>>, line, col, acc) do
    scan_string_part(rest, line, col + 2, acc <> "\\")
  end
  defp scan_string_part(<<"\\n", rest::binary>>, line, col, acc) do
    scan_string_part(rest, line, col + 2, acc <> "\n")
  end
  defp scan_string_part(<<"\\t", rest::binary>>, line, col, acc) do
    scan_string_part(rest, line, col + 2, acc <> "\t")
  end
  defp scan_string_part(<<"\\r", rest::binary>>, line, col, acc) do
    scan_string_part(rest, line, col + 2, acc <> "\r")
  end
  defp scan_string_part(<<"\n", rest::binary>>, line, _col, acc) do
    scan_string_part(rest, line + 1, 1, acc <> "\n")
  end
  defp scan_string_part(<<char::utf8, rest::binary>>, line, col, acc) do
    scan_string_part(rest, line, col + 1, acc <> <<char::utf8>>)
  end
  defp scan_string_part("", line, col, _acc) do
    {:error, "Unterminated string", line, col}
  end
end
