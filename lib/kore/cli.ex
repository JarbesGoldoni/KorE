defmodule Kore.CLI do
  @moduledoc """
  CLI escript entry point for KorE.

  Dispatches commands to specialized sub-modules:
  - `Kore.CLI.Scaffold` — project scaffolding (`new`)
  - `Kore.CLI.Builder` — compilation and execution (`build`, `run`, `test`)
  """

  alias Kore.Formatter

  def main(args \\ []) do
    case args do
      ["new", name] -> Kore.CLI.Scaffold.run(name)
      ["build"] -> Kore.CLI.Builder.build()
      ["clean"] -> clean()
      ["check"] -> check()
      ["test"] -> Kore.CLI.Builder.test()
      ["fmt" | rest] -> format_cli(rest)
      ["format" | rest] -> format_cli(rest)
      ["run"] -> Kore.CLI.Builder.run("Kore.Main")
      ["run", module] -> Kore.CLI.Builder.run(module)
      ["version"] -> IO.puts("KorE #{Kore.version()}")
      ["help" | rest] -> help(rest)
      _ -> print_usage()
    end
  end

  defp print_usage(exit_code \\ 1) do
    IO.puts("""
    KorE toolchain v#{Kore.version()}

    Usage: kore <command> [options]

    Commands:
      new <name>       scaffold a new KorE project
      build            compile .kore files to Elixir then to BEAM
      run [module]     build + run Kore.Main.main() (or given module's main)
      clean            remove build artifacts (_build/)
      check            fast syntax & semantic check without codegen
      test             compile and run project tests
      fmt, format      format .kore source files (--check to verify)
      version          print version
      help [command]   display detailed help for a command
    """)
    if exit_code != nil do
      System.halt(exit_code)
    end
  end

  # ── Command Implementations (kept local — small utilities) ─────────

  defp clean do
    if File.exists?("_build") do
      File.rm_rf!("_build")
      IO.puts("Cleaned build artifacts (_build/).")
    else
      IO.puts("Nothing to clean (_build/ directory does not exist).")
    end
  end

  defp check do
    _config = Kore.CLI.Builder.read_config()
    kore_files = Path.wildcard("lib/**/*.kore") ++ Path.wildcard("test/**/*.kore")

    if kore_files == [] do
      IO.puts("No .kore files found to check.")
    else
      total_errors = Enum.reduce(kore_files, 0, fn file, acc_err ->
        source = File.read!(file)
        case Kore.compile(source, file: file) do
          {:ok, _} ->
            acc_err

          {:error, errors} ->
            IO.puts(Kore.Errors.format_all(errors))
            acc_err + length(errors)
        end
      end)

      if total_errors == 0 do
        IO.puts("Check passed: 0 errors found in #{length(kore_files)} file(s).")
      else
        IO.puts("Check failed: #{total_errors} error(s) found.")
        System.halt(1)
      end
    end
  end

  defp format_cli(args) do
    check_only = "--check" in args
    paths = Enum.reject(args, &(&1 == "--check"))

    files =
      if paths == [] do
        Path.wildcard("lib/**/*.kore") ++ Path.wildcard("test/**/*.kore")
      else
        Enum.flat_map(paths, fn p ->
          if File.dir?(p) do
            Path.wildcard("#{p}/**/*.kore")
          else
            [p]
          end
        end)
      end

    if files == [] do
      IO.puts("No .kore files found to format.")
    else
      needs_formatting = Enum.reduce(files, [], fn file, acc ->
        case Formatter.format_file(file, overwrite: not check_only) do
          {:ok, formatted} ->
            original = File.read!(file)
            if formatted != original do
              [file | acc]
            else
              acc
            end

          {:error, errors} ->
            IO.puts("Error formatting #{file}:")
            IO.puts(Kore.Errors.format_all(errors))
            acc
        end
      end)

      if check_only do
        if needs_formatting != [] do
          IO.puts("The following file(s) need formatting:")
          Enum.each(needs_formatting, &IO.puts("  - #{&1}"))
          System.halt(1)
        else
          IO.puts("All #{length(files)} file(s) are properly formatted.")
        end
      else
        if needs_formatting != [] do
          IO.puts("Formatted #{length(needs_formatting)} file(s):")
          Enum.each(needs_formatting, &IO.puts("  - #{&1}"))
        else
          IO.puts("All #{length(files)} file(s) already formatted.")
        end
      end
    end
  end

  # ── Help Command ───────────────────────────────────────────────────

  defp help([]) do
    print_usage(0)
  end

  defp help(["new"]) do
    IO.puts("""
    Usage: kore new <name>

    Scaffolds a new KorE project structure in a directory named <name>:
      <name>/
      ├── kore.exs        # project configuration
      ├── lib/
      │   └── main.kore   # entry point module
      └── .gitignore
    """)
  end

  defp help(["build"]) do
    IO.puts("""
    Usage: kore build

    Compiles all .kore files in lib/ (and test/) to Elixir source files
    under _build/kore_gen/lib/, synthesizes a mix.exs, and runs mix compile to BEAM.
    """)
  end

  defp help(["clean"]) do
    IO.puts("""
    Usage: kore clean

    Removes the _build/ directory containing transpiled Elixir sources
    and compiled BEAM bytecode artifacts.
    """)
  end

  defp help(["check"]) do
    IO.puts("""
    Usage: kore check

    Performs fast lexical, syntactic, and semantic checking (scopes, closures,
    var-threading, exhaustiveness, minimal types) on all .kore files without
    generating Elixir code or invoking mix compile.
    """)
  end

  defp help(["test"]) do
    IO.puts("""
    Usage: kore test

    Builds the project and executes tests defined in test/ via the BEAM runtime.
    """)
  end

  defp help(["fmt"]) do
    help(["format"])
  end

  defp help(["format"]) do
    IO.puts("""
    Usage: kore fmt [files...] [--check]
           kore format [files...] [--check]

    Formats KorE source files in-place according to standard formatting rules.

    Options:
      --check    Verify if files are formatted without making changes.
                 Exits with status 1 if any files require formatting.
    """)
  end

  defp help(["run"]) do
    IO.puts("""
    Usage: kore run [module]

    Builds the project and executes the entry point.
    If [module] is omitted, executes Kore.Main.main().
    """)
  end

  defp help(["version"]) do
    IO.puts("""
    Usage: kore version

    Prints the version of the KorE compiler toolchain.
    """)
  end

  defp help([unknown]) do
    IO.puts("Unknown command: #{unknown}")
    print_usage()
  end
end
