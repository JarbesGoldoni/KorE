defmodule Kore.FormatterTest do
  use ExUnit.Case, async: true

  alias Kore.Formatter

  test "formats basic module and function" do
    source = """
    module   Math  {
    fun  add( a: Int ,  b: Int ): Int  =  a + b
    }
    """

    assert {:ok, formatted} = Formatter.format(source)
    assert formatted =~ "module Math {"
    assert formatted =~ "fun add(a: Int, b: Int): Int = a + b"
  end

  test "formats data declaration" do
    source = """
    module Models {
    data  User( val name: String , val age: Int = 0 )
    }
    """

    assert {:ok, formatted} = Formatter.format(source)
    assert formatted =~ "data User(val name: String, val age: Int = 0)"
  end

  test "formats sealed declaration" do
    source = """
    module Shapes {
    sealed Shape {
    data Circle(val r: Double)
    data Rect(val w: Double, val h: Double)
    }
    }
    """

    assert {:ok, formatted} = Formatter.format(source)
    assert formatted =~ "sealed Shape {"
    assert formatted =~ "data Circle(val r: Double)"
  end

  test "formatter idempotency" do
    source = """
    module Test {
        fun greet(name: String): String = "Hello, $name!"
    }
    """

    assert {:ok, formatted1} = Formatter.format(source)
    assert {:ok, formatted2} = Formatter.format(formatted1)
    assert formatted1 == formatted2
  end
end
