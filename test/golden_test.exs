defmodule Kore.GoldenTest do
  use ExUnit.Case, async: true

  @cases_dir Path.expand("golden/cases", __DIR__)

  setup_all do
    File.mkdir_p!(@cases_dir)
    :ok
  end

  test "golden test suite" do
    kore_files = Path.wildcard(Path.join(@cases_dir, "*.kore"))

    for kore_path <- kore_files do
      name = Path.basename(kore_path, ".kore")
      expected_path = Path.join(@cases_dir, "#{name}.expected.ex")

      {:ok, compiled} = Kore.compile_file(kore_path)

      if System.get_env("KORE_UPDATE_GOLDEN") == "1" do
        File.write!(expected_path, compiled)
      else
        assert File.exists?(expected_path), "Missing expected file for #{name}.kore"
        expected = File.read!(expected_path)
        assert String.trim(compiled) == String.trim(expected), "Golden mismatch for #{name}.kore"
      end
    end
  end
end
