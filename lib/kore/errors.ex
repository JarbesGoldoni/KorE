defmodule Kore.Errors do
  @moduledoc """
  Compile error diagnostics with file, line:col, message, and source excerpt.

  Errors are collected per-file (report as many as possible, don't stop at first).
  """

  defstruct [:file, :line, :col, :message, :source_line]

  @type t :: %__MODULE__{
          file: String.t(),
          line: pos_integer(),
          col: pos_integer(),
          message: String.t(),
          source_line: String.t() | nil
        }

  @doc "Create a new error."
  def new(file, line, col, message, source_line \\ nil) do
    %__MODULE__{
      file: file,
      line: line,
      col: col,
      message: message,
      source_line: source_line
    }
  end

  @doc "Format an error for display."
  def format(%__MODULE__{} = err) do
    loc = "#{err.file}:#{err.line}:#{err.col}"
    msg = "#{loc}: error: #{err.message}"

    if err.source_line do
      caret = String.duplicate(" ", max(err.col - 1, 0)) <> "^"
      "#{msg}\n  #{err.source_line}\n  #{caret}"
    else
      msg
    end
  end

  @doc "Format a list of errors and return them as a single string."
  def format_all(errors) do
    errors
    |> Enum.map(&format/1)
    |> Enum.join("\n\n")
  end

  @doc "Check if there are any errors."
  def has_errors?(errors), do: errors != []
end
