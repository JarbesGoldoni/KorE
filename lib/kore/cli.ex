defmodule Kore.CLI do
  @moduledoc """
  CLI escript entry point for KorE.
  """

  alias Kore.Formatter

  def main(args \\ []) do
    case args do
      ["new", name] -> new_project(name)
      ["build"] -> build()
      ["clean"] -> clean()
      ["check"] -> check()
      ["test"] -> test()
      ["fmt" | rest] -> format_cli(rest)
      ["format" | rest] -> format_cli(rest)
      ["run"] -> run("Kore.Main")
      ["run", module] -> run(module)
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

  # ── Templates ──────────────────────────────────────────────────────

  @default_kore_exs ~s([name: "<name>", version: "0.1.0"])
  @default_main_kore """
  module Main {
      fun main() {
          println("Hello, KorE!")
      }
  }
  """
  @default_gitignore "_build/\n"

  # ── Command Implementations ────────────────────────────────────────

  defp new_project(name) do
    if File.exists?(name) do
      IO.puts("Error: Directory '#{name}' already exists.")
      System.halt(1)
    end

    File.mkdir_p!("#{name}/lib")
    File.mkdir_p!("#{name}/test")

    priv_dir = case :code.priv_dir(:kore) do
      {:error, :bad_name} -> Path.join(File.cwd!(), "priv")
      path -> to_string(path)
    end

    config_template = Path.join(priv_dir, "templates/kore.exs")
    config_content =
      if File.exists?(config_template) do
        File.read!(config_template)
      else
        @default_kore_exs
      end
      |> String.replace("<name>", name)

    File.write!("#{name}/kore.exs", config_content)

    main_template = Path.join(priv_dir, "templates/main.kore")
    main_content =
      if File.exists?(main_template) do
        File.read!(main_template)
      else
        @default_main_kore
      end

    File.write!("#{name}/lib/main.kore", main_content)

    gitignore_template = Path.join(priv_dir, "templates/gitignore")
    gitignore_content =
      if File.exists?(gitignore_template) do
        File.read!(gitignore_template)
      else
        @default_gitignore
      end

    File.write!("#{name}/.gitignore", gitignore_content)

    IO.puts("Created KorE project '#{name}'.")
  end

  defp read_config do
    if File.exists?("kore.exs") do
      {config, _} = Code.eval_file("kore.exs")
      config
    else
      IO.puts("Error: kore.exs not found in current directory.")
      System.halt(1)
    end
  end

  defp build do
    config = read_config()
    app_name = Keyword.get(config, :name)
    app_version = Keyword.get(config, :version, "0.1.0")
    deps = Keyword.get(config, :deps, [])

    unless app_name do
      IO.puts("Error: :name is required in kore.exs.")
      System.halt(1)
    end

    kore_files = Path.wildcard("lib/**/*.kore") ++ Path.wildcard("test/**/*.kore")
    
    File.mkdir_p!("_build/kore_gen/lib")

    has_errors = Enum.reduce(kore_files, false, fn file, acc ->
      IO.puts("Compiling #{file}...")
      case Kore.compile_file(file) do
        {:ok, elixir_code} ->
          rel_dir = Path.dirname(file)
          dest_dir = Path.join(["_build/kore_gen", rel_dir])
          File.mkdir_p!(dest_dir)
          base_name = Path.basename(file, ".kore")
          dest_path = Path.join(dest_dir, "#{base_name}.ex")
          File.write!(dest_path, elixir_code)
          acc

        {:error, errors} ->
          if Code.ensure_loaded?(Kore.Errors) && function_exported?(Kore.Errors, :format_all, 1) do
            IO.puts(Kore.Errors.format_all(errors))
          else
            IO.inspect(errors)
          end
          true
      end
    end)

    if has_errors do
      IO.puts("Compilation failed.")
      System.halt(1)
    end

    mix_exs = """
    defmodule #{Macro.camelize(app_name)}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{app_name},
          version: "#{app_version}",
          elixir: "~> 1.14",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        #{inspect(deps)}
      end
    end
    """
    File.write!("_build/kore_gen/mix.exs", mix_exs)

    IO.puts("Running mix compile in _build/kore_gen...")
    {output, status} = System.cmd("mix", ["deps.get"], cd: "_build/kore_gen", stderr_to_stdout: true)
    IO.write(output)
    if status != 0 do
      IO.puts("mix deps.get failed")
      System.halt(status)
    end

    {output, status} = System.cmd("mix", ["compile"], cd: "_build/kore_gen", stderr_to_stdout: true)
    IO.write(output)
    if status != 0 do
      IO.puts("mix compile failed")
      System.halt(status)
    end
  end

  defp clean do
    if File.exists?("_build") do
      File.rm_rf!("_build")
      IO.puts("Cleaned build artifacts (_build/).")
    else
      IO.puts("Nothing to clean (_build/ directory does not exist).")
    end
  end

  defp check do
    _config = read_config()
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

  defp test do
    build()
    IO.puts("Running tests in _build/kore_gen...")
    {output, status} = System.cmd("mix", ["test"], cd: "_build/kore_gen", stderr_to_stdout: true)
    IO.write(output)
    if status != 0 do
      System.halt(status)
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

  defp run(module_or_func) do
    build()

    target =
      cond do
        String.ends_with?(module_or_func, ")") ->
          module_or_func

        Regex.match?(~r/\.[a-z_][a-zA-Z0-9_]*$/, module_or_func) ->
          "#{module_or_func}()"

        true ->
          "#{module_or_func}.main()"
      end

    IO.puts("Running #{target}...")
    {output, status} = System.cmd("mix", ["run", "-e", target], cd: "_build/kore_gen", stderr_to_stdout: true)
    IO.write(output)
    if status != 0 do
      System.halt(status)
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
