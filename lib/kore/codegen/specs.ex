defmodule Kore.Codegen.Specs do
  alias Kore.AST.{TypeRef, FunctionType}

  def type_to_spec(type, type_index \\ %{})
  def type_to_spec(nil, _type_index), do: ":ok"
  def type_to_spec(%FunctionType{} = t, type_index) do
    params = Enum.map(t.param_types, &type_to_spec(&1, type_index)) |> Enum.join(", ")
    ret = type_to_spec(t.return_type, type_index)
    "(#{params} -> #{ret})"
  end
  def type_to_spec(%TypeRef{name: "Int", nullable: false}, _), do: "integer()"
  def type_to_spec(%TypeRef{name: "Double", nullable: false}, _), do: "float()"
  def type_to_spec(%TypeRef{name: "Boolean", nullable: false}, _), do: "boolean()"
  def type_to_spec(%TypeRef{name: "String", nullable: false}, _), do: "String.t()"
  def type_to_spec(%TypeRef{name: "Atom", nullable: false}, _), do: "atom()"
  def type_to_spec(%TypeRef{name: "Unit", nullable: false}, _), do: ":ok"
  def type_to_spec(%TypeRef{name: "Any", nullable: false}, _), do: "term()"
  def type_to_spec(%TypeRef{name: "Pid", nullable: false}, _), do: "pid()"
  def type_to_spec(%TypeRef{name: "List", params: [t], nullable: false}, type_index), do: "[#{type_to_spec(t, type_index)}]"
  def type_to_spec(%TypeRef{name: "Map", params: [k, v], nullable: false}, type_index), do: "%{optional(#{type_to_spec(k, type_index)}) => #{type_to_spec(v, type_index)}}"
  def type_to_spec(%TypeRef{name: "Pair", params: [a, b], nullable: false}, type_index), do: "{#{type_to_spec(a, type_index)}, #{type_to_spec(b, type_index)}}"
  def type_to_spec(%TypeRef{name: "Result", params: [t, e], nullable: false}, type_index), do: "{:ok, #{type_to_spec(t, type_index)}} | {:error, #{type_to_spec(e, type_index)}}"
  def type_to_spec(%TypeRef{nullable: true} = t, type_index) do
    "#{type_to_spec(%{t | nullable: false}, type_index)} | nil"
  end
  def type_to_spec(%TypeRef{name: name, nullable: false}, type_index) do
    case Map.get(type_index, name) do
      %{module: mod} -> "#{mod}.t()"
      _ -> "Kore.#{name}.t()"
    end
  end

  def type_to_guard(type, param, type_index \\ %{})
  def type_to_guard(nil, _, _), do: nil
  def type_to_guard(%FunctionType{}, _, _), do: nil
  def type_to_guard(%TypeRef{nullable: true}, _, _), do: nil
  def type_to_guard(%TypeRef{name: "Int", nullable: false}, param, _), do: "is_integer(#{param})"
  def type_to_guard(%TypeRef{name: "Double", nullable: false}, param, _), do: "is_float(#{param})"
  def type_to_guard(%TypeRef{name: "Boolean", nullable: false}, param, _), do: "is_boolean(#{param})"
  def type_to_guard(%TypeRef{name: "String", nullable: false}, param, _), do: "is_binary(#{param})"
  def type_to_guard(%TypeRef{name: "Atom", nullable: false}, param, _), do: "is_atom(#{param})"
  def type_to_guard(%TypeRef{name: "Unit", nullable: false}, _param, _), do: nil
  def type_to_guard(%TypeRef{name: "Any", nullable: false}, _param, _), do: nil
  def type_to_guard(%TypeRef{name: "Pid", nullable: false}, param, _), do: "is_pid(#{param})"
  def type_to_guard(%TypeRef{name: "List", nullable: false}, param, _), do: "is_list(#{param})"
  def type_to_guard(%TypeRef{name: "Map", nullable: false}, param, _), do: "is_map(#{param})"
  def type_to_guard(%TypeRef{name: "Pair", nullable: false}, param, _), do: "is_tuple(#{param})"
  def type_to_guard(%TypeRef{name: "Result", nullable: false}, _param, _), do: nil
  def type_to_guard(%TypeRef{name: name, nullable: false}, param, type_index) do
    case Map.get(type_index, name) do
      %{module: mod} -> "is_struct(#{param}, #{mod})"
      _ -> "is_struct(#{param}, Kore.#{name})"
    end
  end

  def generate_spec(%Kore.AST.FunDecl{} = fun_decl, _module_name, type_index \\ %{}) do
    params = Enum.map(fun_decl.params || [], fn p -> type_to_spec(p.type, type_index) end)
    ret = type_to_spec(fun_decl.return_type, type_index)
    "@spec #{Kore.Prelude.to_snake_case(fun_decl.name)}(#{Enum.join(params, ", ")}) :: #{ret}"
  end

  def generate_guards(%Kore.AST.FunDecl{} = fun_decl, type_index \\ %{}) do
    guards =
      (fun_decl.params || [])
      |> Enum.map(fn p ->
        guard = type_to_guard(p.type, Kore.Prelude.to_snake_case(p.name), type_index)
        guard
      end)
      |> Enum.reject(&is_nil/1)

    case guards do
      [] -> nil
      _ -> Enum.join(guards, " and ")
    end
  end
end
