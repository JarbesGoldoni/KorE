defmodule Kore.ErrorTest do
  use ExUnit.Case, async: true

  test "val reassignment error" do
    source = """
    module ValError {
        fun test() {
            val x = 1
            x = 2
        }
    }
    """
    assert {:error, [err]} = Kore.compile(source, file: "val_error.kore")
    assert err.message =~ "cannot reassign 'val' variable 'x'"
  end

  test "var reassignment in lambda error" do
    source = """
    module LambdaVarError {
        fun test(list: List<Int>) {
            var x = 1
            list.map { x = 2 }
        }
    }
    """
    assert {:error, [err]} = Kore.compile(source, file: "lambda_var_error.kore")
    assert err.message =~ "cannot rebind 'x' inside a lambda"
  end

  test "non-exhaustive when error" do
    source = """
    module ExhaustiveError {
        sealed Shape {
            data Circle(val r: Double)
            data Rect(val w: Double, val h: Double)
        }

        fun area(s: Shape): Double = when (s) {
            is Circle(val r) -> 3.14 * r
        }
    }
    """
    assert {:error, [err]} = Kore.compile(source, file: "exhaustive_error.kore")
    assert err.message =~ "non-exhaustive 'when'"
  end

  test "call arity mismatch error" do
    source = """
    module ArityError {
        fun add(a: Int, b: Int): Int = a + b
        fun test(): Int = add(1)
    }
    """
    assert {:error, [err]} = Kore.compile(source, file: "arity_error.kore")
    assert err.message =~ "function 'add' expects 2..2 arguments, got 1"
  end

  test "type literal mismatch error" do
    source = """
    module TypeMismatchError {
        fun test() {
            val x: Int = "hi"
        }
    }
    """
    assert {:error, [err]} = Kore.compile(source, file: "type_mismatch_error.kore")
    assert err.message =~ "type mismatch: expected 'Int', got string literal"
  end

  test "unknown function error" do
    source = """
    module UnknownFuncError {
        fun test() {
            foo()
        }
    }
    """
    assert {:error, [err]} = Kore.compile(source, file: "unknown_func_error.kore")
    assert err.message =~ "undefined variable 'foo'"
  end

  test "file name and module name mismatch error" do
    source = """
    module Bar {
        fun test() {}
    }
    """
    assert {:error, [err]} = Kore.compile(source, file: "lib/foo.kore")
    assert err.message =~ "file name 'foo.kore' does not match module name 'Bar'"
  end

  test "early return error" do
    source = """
    module EarlyReturnError {
        fun test(): Int {
            return 1
            val x = 2
            return x
        }
    }
    """
    assert {:error, [err]} = Kore.compile(source, file: "early_return_error.kore")
    assert err.message =~ "early return not supported"
  end
end
