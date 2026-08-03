defmodule Kore.LexerTest do
  use ExUnit.Case

  alias Kore.Lexer

  test "keywords" do
    assert {:ok, [{:module, :module, 1, 1}]} = Lexer.tokenize("module")
    assert {:ok, [{:fun, :fun, 1, 1}]} = Lexer.tokenize("fun")
    assert {:ok, [{:true, :true, 1, 1}]} = Lexer.tokenize("true")
  end

  test "identifiers" do
    assert {:ok, [{:identifier, "myVar", 1, 1}]} = Lexer.tokenize("myVar")
    assert {:ok, [{:type_identifier, "MyType", 1, 1}]} = Lexer.tokenize("MyType")
  end

  test "literals" do
    assert {:ok, [{:integer, 42, 1, 1}]} = Lexer.tokenize("42")
    assert {:ok, [{:integer, 1000000, 1, 1}]} = Lexer.tokenize("1_000_000")
    assert {:ok, [{:double, 3.14, 1, 1}]} = Lexer.tokenize("3.14")
    assert {:ok, [{:atom, :ok, 1, 1}]} = Lexer.tokenize(":ok")
  end

  test "strings" do
    assert {:ok, [{:string, "hello", 1, 1}]} = Lexer.tokenize("\"hello\"")
  end

  test "string interpolation simple" do
    assert {:ok, tokens} = Lexer.tokenize("\"hello $name\"")
    assert [
             {:string_start, :string_start, 1, 1},
             {:string_part, "hello ", 1, 2},
             {:interp_start, :interp_start, 1, 8},
             {:identifier, "name", 1, 9},
             {:interp_end, :interp_end, 1, 13},
             {:string_end, :string_end, 1, 13}
           ] = tokens
  end

  test "string interpolation complex" do
    assert {:ok, tokens} = Lexer.tokenize("\"hello ${1 + 2}\"")
    assert [
             {:string_start, :string_start, 1, 1},
             {:string_part, "hello ", 1, 2},
             {:interp_start, :interp_start, 1, 8},
             {:integer, 1, 1, 10},
             {:plus, :plus, 1, 12},
             {:integer, 2, 1, 14},
             {:interp_end, :interp_end, 1, 15},
             {:string_end, :string_end, 1, 16}
           ] = tokens
  end

  test "operators" do
    assert {:ok, [{:plus, :plus, 1, 1}]} = Lexer.tokenize("+")
    assert {:ok, [{:arrow, :arrow, 1, 1}]} = Lexer.tokenize("->")
    assert {:ok, [{:eq_eq, :eq_eq, 1, 1}]} = Lexer.tokenize("==")
    assert {:ok, [{:less_eq, :less_eq, 1, 1}]} = Lexer.tokenize("<=")
  end

  test "comments" do
    assert {:ok, [{:integer, 1, 1, 1}, {:newline, :newline, 1, 13}, {:integer, 2, 2, 1}]} = Lexer.tokenize("1 // comment\n2")
    assert {:ok, [{:integer, 1, 1, 1}, {:integer, 2, 1, 17}]} = Lexer.tokenize("1 /* comment */ 2")
  end

  test "newlines" do
    assert {:ok, [{:integer, 1, 1, 1}, {:newline, :newline, 1, 2}, {:integer, 2, 3, 1}]} = Lexer.tokenize("1\n\n2")
  end

  test "errors" do
    assert {:error, [err]} = Lexer.tokenize("1 %^&")
    assert err.message == "Invalid character"
  end
end
