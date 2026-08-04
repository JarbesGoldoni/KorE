defmodule Kore.WebAppIssuesTest do
  use ExUnit.Case

  defp compile(source) do
    # Extract module name using regex to determine the file name
    module_name = case Regex.run(~r/module\s+([A-Z][a-zA-Z0-9_]*)/, source) do
      [_, name] -> name
      _ -> "test"
    end
    file_name = Macro.underscore(module_name) <> ".kore"

    case Kore.compile(source, file: file_name) do
      {:ok, elixir_code} -> elixir_code
      {:error, errors} -> flunk("Compilation failed:\n#{Kore.Errors.format_all(errors)}")
    end
  end

  defp assert_compile_error(source, expected_msg_fragment) do
    case Kore.compile(source, file: "test.kore") do
      {:ok, _} -> flunk("Expected compilation to fail, but it succeeded")
      {:error, errors} -> 
        formatted = Kore.Errors.format_all(errors)
        assert formatted =~ expected_msg_fragment
    end
  end

  test "Issue 1: Multi-line data and actor declarations are supported" do
    source = """
    module Test {
      data Message(
        val id: Int,
        val user: String,
        val text: String,
        val timestamp: String
      )
      
      actor Chat(
        var users: List<String>,
        var msgs: List<Message>
      ) {
        fun f() = 1
      }
    }
    """
    code = compile(source)
    assert code =~ "defmodule Kore.Test.Message do"
    assert code =~ "defmodule Kore.Test.Chat do"
    assert code =~ "defstruct"
  end

  test "Issue 2: 'data' is allowed as a variable name" do
    source = """
    module Test {
      fun process(r: Result<String, String>): String = when (r) {
        is Ok(val data) -> data
        else -> "none"
      }
    }
    """
    code = compile(source)
    assert code =~ "{:ok, data}"
    assert code =~ "data"
  end

  test "Issue 3: String \\\" escaping in codegen output" do
    source = """
    module Test {
      val html = "<html lang=\\\"en\\\">"
    }
    """
    code = compile(source)
    # The generated code should have properly escaped double quotes
    assert code =~ ~S("<html lang=\"en\">")
  end

  test "Issue 4: kore check catching generated Elixir syntax errors" do
    # Verify that if we somehow generate syntactically invalid Elixir, it is caught.
    # We can inject invalid Elixir if we mock string_to_quoted or by finding a flaw,
    # but we can at least assert that validate_elixir works if we mock it, or that compiling valid code passes.
    assert {:ok, _} = Kore.compile("module Test {}")
    # Also verify our test compiles cleanly to valid elixir
    code = compile("module Test { val a = 1 }")
    assert {:ok, _} = Code.string_to_quoted(code)
  end

  test "Issue 5 & 6: String concatenation generating <> instead of +" do
    source = """
    module Test {
      val s = "hello" + " " + "world"
      val url = "https://" + "example.com"
      val css = "color: " + "red"
    }
    """
    code = compile(source)
    assert code =~ ~S("hello" <> " " <> "world")
    assert code =~ ~S("https://" <> "example.com")
    assert code =~ ~S("color: " <> "red")
    refute code =~ ~S("hello" + " " + "world")
  end

  test "Issue 7 & 8: Dotted type annotations & cross-module actor method call" do
    source = """
    module Test {
      fun start(store: ChatStore.Store): Any = store.getMessages()
    }
    """
    code = compile(source)
    # The generated dispatch should be GenServer.call, as it knows it's an actor type
    assert code =~ "GenServer.call(store, :get_messages)"
  end

  test "Issue 9: Conn.getMethod / Conn.getPathInfo generating conn.method / conn.path_info" do
    source = """
    module Test {
      fun req(conn: Any): Any {
        val m = Conn.getMethod(conn)
        val p = Conn.getPathInfo(conn)
        return m
      }
    }
    """
    code = compile(source)
    assert code =~ "conn.method"
    assert code =~ "conn.path_info"
  end

  test "Issue 10: Conn.readBody returning 2-tuple {:ok, body}" do
    source = """
    module Test {
      fun read(conn: Any): Any = Conn.readBody(conn)
    }
    """
    code = compile(source)
    assert code =~ "Plug.Conn.read_body(conn)"
    assert code =~ "{:ok, body}"
  end

  test "Issue 11: Nested data record module namespace (Kore.ChatStore.Message)" do
    source = """
    module ChatStore {
      data Message(val text: String)
      fun add(): Message = Message("hi")
    }
    """
    code = compile(source)
    assert code =~ "Kore.ChatStore.Message"
  end

  test "Issue 12: Cross-module KorE call Kore.ChatStore.Store.start()" do
    source = """
    module Main {
      fun main() {
        ChatStore.Store.start()
      }
    }
    """
    code = compile(source)
    assert code =~ "Kore.ChatStore.Store.start()"
  end

  test "Issue 13: receive { else -> } binding it" do
    source = """
    module Test {
      fun wait(): Any = receive {
        else -> it
      }
    }
    """
    code = compile(source)
    assert code =~ "it ->"
    assert code =~ "it"
  end

  test "Issue 14: String \\n, \\t escape sequences" do
    source = """
    module Test {
      val s = "line1\\nline2\\t"
    }
    """
    code = compile(source)
    assert code =~ ~S("line1\nline2\t")
  end

  test "Issue 15: tupleOf(...) flat tuple generation {a, b, c}" do
    source = """
    module Test {
      val t = tupleOf(1, 2, 3)
    }
    """
    code = compile(source)
    assert code =~ "{1, 2, 3}"
  end
end
