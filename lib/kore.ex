defmodule Kore do
  @moduledoc """
  KorE — A Kotlin-flavoured language targeting the Erlang VM (BEAM)
  by transpiling to Elixir source code.

  Public compile API.
  """

  alias Kore.{Lexer, Parser}
  alias Kore.Semantics.{Scopes, Closures, VarThreading, Exhaustive}
  alias Kore.Codegen

  @version "0.1.0"

  def version, do: @version

  @doc """
  Compile a single .kore source string to Elixir source code.

  Returns `{:ok, elixir_source}` or `{:error, [%Kore.Errors{}]}`.
  """
  def compile(source, opts \\ []) do
    file = Keyword.get(opts, :file, "nofile")
    source_lines = String.split(source, "\n")

    with {:ok, tokens} <- Lexer.tokenize(source, file),
         {:ok, ast} <- Parser.parse(tokens, file, source_lines),
         {:ok, ast} <- run_semantic_passes(ast, file, source_lines),
         {:ok, elixir_code} <- Codegen.Elixir.generate(ast, file),
         :ok <- validate_elixir(elixir_code, file) do
      {:ok, elixir_code}
    end
  end

  defp validate_elixir(elixir_code, file) do
    case Code.string_to_quoted(elixir_code) do
      {:ok, _} ->
        :ok

      {:error, {meta, error_msg, token}} ->
        line = Keyword.get(meta, :line, 1)
        msg = "Generated Elixir syntax error: #{to_string(error_msg)}#{to_string(token)} (Elixir line #{line})"
        err = Kore.Errors.new(file, 1, 1, msg, nil)
        {:error, [err]}
    end
  end

  @doc """
  Compile a .kore file from disk.
  """
  def compile_file(path) do
    source = File.read!(path)
    compile(source, file: path)
  end

  # ── Semantic passes (in order per §6.3) ────────────────────────────

  defp run_semantic_passes(ast, file, source_lines) do
    with {:ok, ast} <- Scopes.resolve(ast, file, source_lines),
         {:ok, ast} <- Closures.check(ast, file, source_lines),
         {:ok, ast} <- VarThreading.rewrite(ast, file, source_lines),
         {:ok, ast} <- Exhaustive.check(ast, file, source_lines),
         {:ok, ast} <- Kore.Typecheck.check(ast, file, source_lines) do
      {:ok, ast}
    end
  end
end
