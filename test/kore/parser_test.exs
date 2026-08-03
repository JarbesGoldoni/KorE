defmodule Kore.ParserTest do
  use ExUnit.Case
  alias Kore.AST
  alias Kore.Parser

  def parse(tokens) do
    tokens = tokens ++ [{:eof, nil, 0, 0}]
    Parser.parse(tokens, "test.kore", [])
  end

  test "parses a basic module with function" do
    tokens = [
      {:module, nil, 1, 1}, {:type_identifier, "Main", 1, 8}, {:lbrace, nil, 1, 13},
      {:fun, nil, 2, 3}, {:identifier, "main", 2, 7}, {:lparen, nil, 2, 11}, {:rparen, nil, 2, 12},
      {:lbrace, nil, 2, 14},
      {:identifier, "println", 3, 5}, {:lparen, nil, 3, 12}, {:string, "Hello", 3, 13}, {:rparen, nil, 3, 20},
      {:rbrace, nil, 4, 3},
      {:rbrace, nil, 5, 1}
    ]
    
    assert {:ok, file} = parse(tokens)
    assert file.module.name == "Main"
    assert [fun] = file.module.declarations
    assert fun.name == "main"
    assert [%AST.Call{function: %AST.VarRef{name: "println"}, args: [%AST.Literal{type: :string, value: "Hello"}]}] = fun.body.statements
  end

  test "parses expressions" do
    tokens = [
      {:module, nil, 1, 1}, {:type_identifier, "Main", 1, 8}, {:lbrace, nil, 1, 13},
      {:val, nil, 2, 3}, {:identifier, "x", 2, 7}, {:equal, nil, 2, 9}, 
      {:int, 1, 2, 11}, {:plus, nil, 2, 13}, {:int, 2, 2, 15}, {:star, nil, 2, 17}, {:int, 3, 2, 19},
      {:rbrace, nil, 3, 1}
    ]
    
    assert {:ok, file} = parse(tokens)
    assert [val] = file.module.declarations
    assert val.name == "x"
    assert %AST.BinOp{
      op: :plus,
      left: %AST.Literal{value: 1},
      right: %AST.BinOp{op: :star, left: %AST.Literal{value: 2}, right: %AST.Literal{value: 3}}
    } = val.value
  end
end
