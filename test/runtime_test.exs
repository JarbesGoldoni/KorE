defmodule Kore.RuntimeTest do
  use ExUnit.Case, async: false

  @compile {:no_warn_undefined, [
    Kore.Arithmetic,
    Kore.VarThreadingTest,
    Kore.ResultTest,
    Kore.ActorTest.Counter,
    Kore.PreludeTest,
    Kore.NullSafetyTest,
    Kore.NullSafetyTest.User
  ]}

  defp compile_and_eval(source, filename) do
    assert {:ok, code} = Kore.compile(source, file: filename)
    Code.compile_string(code)
    :ok
  end

  test "arithmetic and string operations" do
    source = """
    module Arithmetic {
        fun calc(a: Int, b: Int): Int = a * 2 + b
        fun greet(name: String): String = "Hello, $name!"
    }
    """
    compile_and_eval(source, "arithmetic.kore")
    assert Kore.Arithmetic.calc(5, 3) == 13
    assert Kore.Arithmetic.greet("KorE") == "Hello, KorE!"
  end

  test "var threading correctness (if, when, multi-var)" do
    source = """
    module VarThreadingTest {
        fun singleIf(cond: Boolean): Int {
            var x = 10
            if (cond) {
                x = 20
            }
            return x
        }

        fun multiIf(cond: Boolean): Pair<Int, Int> {
            var a = 1
            var b = 2
            if (cond) {
                a = 10
                b = 20
            }
            return Pair(a, b)
        }

        fun whenThreading(n: Int): String {
            var msg = "start"
            when (n) {
                0 -> { msg = "zero" }
                1 -> { msg = "one" }
                else -> { msg = "other" }
            }
            return msg
        }
    }
    """
    compile_and_eval(source, "var_threading_test.kore")
    assert Kore.VarThreadingTest.single_if(true) == 20
    assert Kore.VarThreadingTest.single_if(false) == 10
    assert Kore.VarThreadingTest.multi_if(true) == {10, 20}
    assert Kore.VarThreadingTest.multi_if(false) == {1, 2}
    assert Kore.VarThreadingTest.when_threading(0) == "zero"
    assert Kore.VarThreadingTest.when_threading(1) == "one"
    assert Kore.VarThreadingTest.when_threading(5) == "other"
  end

  test "Result matching" do
    source = """
    module ResultTest {
        fun parse(s: String): Result<Int, String> =
            if (s == "42") Ok(42) else Error("invalid")

        fun check(s: String): String = when (parse(s)) {
            is Ok(val v) -> "ok: $v"
            is Error(val e) -> "err: $e"
        }
    }
    """
    compile_and_eval(source, "result_test.kore")
    assert Kore.ResultTest.check("42") == "ok: 42"
    assert Kore.ResultTest.check("99") == "err: invalid"
  end

  test "actor Counter behaviour" do
    source = """
    module ActorTest {
        actor Counter(var count: Int = 0) {
            fun increment() { count = count + 1 }
            fun add(n: Int) { count = count + n }
            fun get(): Int = count
        }
    }
    """
    compile_and_eval(source, "actor_test.kore")
    pid = Kore.ActorTest.Counter.start(10)
    Kore.ActorTest.Counter.increment(pid)
    Kore.ActorTest.Counter.add(pid, 5)
    assert Kore.ActorTest.Counter.get(pid) == 16
  end

  test "prelude functions and collections" do
    source = """
    module PreludeTest {
        fun processList(list: List<Int>): Int {
            val doubled = list.map { it * 2 }
            return doubled.fold(0) { acc, x -> acc + x }
        }

        fun stringOps(s: String): String {
            val trimmed = s.trim()
            val upper = trimmed.uppercase()
            return upper
        }
    }
    """
    compile_and_eval(source, "prelude_test.kore")
    assert Kore.PreludeTest.process_list([1, 2, 3]) == 12
    assert Kore.PreludeTest.string_ops("  hello  ") == "HELLO"
  end

  test "null-safety operators (?. ?: !!)" do
    source = """
    module NullSafetyTest {
        data User(val name: String)

        fun safeName(u: User?): String? = u?.name
        fun elvisName(u: User?): String = u?.name ?: "default"
        fun forcedName(u: User?): String = u!!.name
    }
    """
    compile_and_eval(source, "null_safety_test.kore")
    u = Kore.NullSafetyTest.User.new("Diego")
    assert Kore.NullSafetyTest.safe_name(u) == "Diego"
    assert Kore.NullSafetyTest.safe_name(nil) == nil

    assert Kore.NullSafetyTest.elvis_name(u) == "Diego"
    assert Kore.NullSafetyTest.elvis_name(nil) == "default"

    assert Kore.NullSafetyTest.forced_name(u) == "Diego"
    assert_raise RuntimeError, fn ->
      Kore.NullSafetyTest.forced_name(nil)
    end
  end
end
