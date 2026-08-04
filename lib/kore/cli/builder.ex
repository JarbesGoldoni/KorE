defmodule Kore.CLI.Builder do
  @moduledoc """
  Handles `kore build` and `kore run` — compilation and execution.
  """

  def build do
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
          if Code.ensure_loaded?(Kore.Errors) and function_exported?(Kore.Errors, :format_all, 1) do
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

  def run(module_or_func) do
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

  def test do
    build()
    IO.puts("Running tests in _build/kore_gen...")
    {output, status} = System.cmd("mix", ["test"], cd: "_build/kore_gen", stderr_to_stdout: true)
    IO.write(output)
    if status != 0 do
      System.halt(status)
    end
  end

  def read_config do
    if File.exists?("kore.exs") do
      {config, _} = Code.eval_file("kore.exs")
      config
    else
      IO.puts("Error: kore.exs not found in current directory.")
      System.halt(1)
    end
  end
end
