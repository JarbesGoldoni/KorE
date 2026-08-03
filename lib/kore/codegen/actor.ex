defmodule Kore.Codegen.Actor do
  alias Kore.Prelude

  def generate(actor_decl, parent_module \\ nil) do
    name = actor_decl.name
    elixir_name = if parent_module, do: "#{parent_module}.#{name}", else: "Kore.#{name}"
    
    state_map = Enum.map(actor_decl.fields, fn f ->
      p = Prelude.to_snake_case(f.name)
      "#{p}: #{p}"
    end) |> Enum.join(", ")

    start_params = Enum.map(actor_decl.fields, fn f ->
      p = Prelude.to_snake_case(f.name)
      if f.default do
        "#{p} \\\\ #{Kore.Codegen.Elixir.expr(f.default)}"
      else
        p
      end
    end) |> Enum.join(", ")

    client_api = Enum.map(actor_decl.methods, fn m ->
      method_name = Prelude.to_snake_case(m.name)
      params = (m.params || []) |> Enum.map(&Prelude.to_snake_case(&1.name))
      
      call_type = if m.return_type == nil or (is_map(m.return_type) and Map.get(m.return_type, :name) == "Unit"), do: "cast", else: "call"
      
      args_list = if length(params) == 0 do
        ":#{method_name}"
      else
        "{:#{method_name}, #{Enum.join(params, ", ")}}"
      end
      
      param_str = if length(params) == 0 do
        "pid"
      else
        "pid, #{Enum.join(params, ", ")}"
      end
      
      "  def #{method_name}(#{param_str}), do: GenServer.#{call_type}(pid, #{args_list})"
    end) |> Enum.join("\n")

    server_callbacks = Enum.map(actor_decl.methods, fn m ->
      method_name = Prelude.to_snake_case(m.name)
      params = (m.params || []) |> Enum.map(&Prelude.to_snake_case(&1.name))
      is_cast = (m.return_type == nil or (is_map(m.return_type) and Map.get(m.return_type, :name) == "Unit"))
      
      args_pattern = if length(params) == 0 do
        ":#{method_name}"
      else
        "{:#{method_name}, #{Enum.join(params, ", ")}}"
      end

      # destructure state
      prologue = Enum.map(actor_decl.fields, fn f ->
        name = Prelude.to_snake_case(f.name)
        "    #{name} = state.#{name}"
      end) |> Enum.join("\n")

      body = if is_map(m.body) and m.body.__struct__ == Kore.AST.Block do
        Enum.map(m.body.statements, fn s -> "    " <> Kore.Codegen.Elixir.expr(s) end) |> Enum.join("\n")
      else
        "    " <> Kore.Codegen.Elixir.expr(m.body)
      end
      
      # var fields writeback
      var_fields = Enum.filter(actor_decl.fields, fn f -> f.mutable end)
      writeback = Enum.map(var_fields, fn f ->
        name = Prelude.to_snake_case(f.name)
        "#{name}: #{name}"
      end) |> Enum.join(", ")
      
      epilogue_state = if length(var_fields) > 0 do
        "%{state | #{writeback}}"
      else
        "state"
      end

      if is_cast do
        """
          @impl true
          def handle_cast(#{args_pattern}, state) do
        #{prologue}
        #{body}
            {:noreply, #{epilogue_state}}
          end
        """
      else
        """
          @impl true
          def handle_call(#{args_pattern}, _from, state) do
        #{prologue}
            kore_ret = (fn -> 
        #{body}
            end).()
            {:reply, kore_ret, #{epilogue_state}}
          end
        """
      end
    end) |> Enum.join("\n")

    """
    defmodule #{elixir_name} do
      use GenServer
      
      # -- client API --
      def start(#{start_params}) do
        {:ok, pid} = GenServer.start_link(__MODULE__, %{#{state_map}})
        pid
      end
      
    #{client_api}

      # -- server callbacks --
      @impl true
      def init(state), do: {:ok, state}
      
    #{server_callbacks}
    end
    """
  end
end
