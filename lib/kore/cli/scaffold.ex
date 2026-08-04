defmodule Kore.CLI.Scaffold do
  @moduledoc """
  Handles `kore new <name>` — project scaffolding.
  """

  @default_kore_exs ~s([name: "<name>", version: "0.1.0"])
  @default_main_kore """
  module Main {
      fun main() {
          println("Hello, KorE!")
      }
  }
  """
  @default_gitignore "_build/\n"

  def run(name) do
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
end
