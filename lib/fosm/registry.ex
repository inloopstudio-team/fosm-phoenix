defmodule Fosm.Registry do
  @moduledoc """
  Registry for FOSM state machine models.
  
  This module provides a centralized registry for all FOSM-enabled models
  in the application. It supports:
  
  - Auto-registration of models at boot time
  - Runtime registration/deregistration
  - Lookup by slug or module name
  - Lifecycle introspection
  
  ## Registration
  
  Models are automatically registered when the application starts if they:
  1. Use `Fosm.Lifecycle`
  2. Are listed in the application config
  
  ## Usage
  
      # Register a model
      Fosm.Registry.register("invoice", MyApp.Invoice)
      
      # Lookup by slug
      Fosm.Registry.lookup("invoice")
      # => {:ok, MyApp.Invoice}
      
      # Lookup by slug (bang version)
      Fosm.Registry.lookup!("invoice")
      # => MyApp.Invoice
      
      # List all registered models
      Fosm.Registry.all()
      # => %{"invoice" => MyApp.Invoice, "order" => MyApp.Order}
      
      # Get lifecycle for a model
      Fosm.Registry.lifecycle("invoice")
      # => {:ok, %Fosm.Lifecycle.Definition{...}}
      
      # Get available events for a record
      Fosm.Registry.available_events("invoice", invoice)
      # => {:ok, [:send_invoice, :cancel]}
  """
  
  use GenServer
  
  require Logger
  
  @table :fosm_registry
  
  # Client API
  
  @doc """
  Starts the registry GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a FOSM model with the given slug.
  
  ## Examples
  
      iex> Fosm.Registry.register("invoice", MyApp.Invoice)
      :ok
      
      iex> Fosm.Registry.register("invoice", MyApp.Invoice, auto_register: true)
      :ok
  """
  @spec register(String.t(), module(), keyword()) :: :ok | {:error, term()}
  def register(slug, module, opts \\ []) when is_binary(slug) and is_atom(module) do
    GenServer.call(__MODULE__, {:register, slug, module, opts})
  end
  
  @doc """
  Unregisters a FOSM model by slug.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(slug) when is_binary(slug) do
    GenServer.call(__MODULE__, {:unregister, slug})
  end
  
  @doc """
  Looks up a FOSM module by its registered slug.
  
  Returns `{:ok, module}` if found, `:error` otherwise.
  """
  @spec lookup(String.t()) :: {:ok, module()} | :error
  def lookup(slug) when is_binary(slug) do
    case :ets.lookup(@table, slug) do
      [{^slug, module, _meta}] -> {:ok, module}
      [] -> :error
    end
  end
  
  @doc """
  Looks up a FOSM module by slug, raising if not found.
  """
  @spec lookup!(String.t()) :: module()
  def lookup!(slug) when is_binary(slug) do
    case lookup(slug) do
      {:ok, module} -> module
      :error -> raise Fosm.Errors.RegistryNotFound, slug: slug
    end
  end
  
  @doc """
  Returns all registered FOSM models as a map of slug => module.
  """
  @spec all() :: %{String.t() => module()}
  def all do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {slug, module, _meta} -> {slug, module} end)
    |> Enum.into(%{})
  end
  
  @doc """
  Returns all registered slugs.
  """
  @spec slugs() :: [String.t()]
  def slugs do
    :ets.select(@table, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end
  
  @doc """
  Gets the lifecycle definition for a registered model.
  """
  @spec lifecycle(String.t()) :: {:ok, map()} | {:error, term()}
  def lifecycle(slug) when is_binary(slug) do
    with {:ok, module} <- lookup(slug),
         true <- function_exported?(module, :fosm_lifecycle, 0) do
      {:ok, module.fosm_lifecycle()}
    else
      :error -> {:error, :not_found}
      false -> {:error, :not_a_fosm_model}
    end
  end
  
  @doc """
  Gets available events for a record of a registered model.
  """
  @spec available_events(String.t(), struct()) :: {:ok, [atom()]} | {:error, term()}
  def available_events(slug, record) when is_binary(slug) and is_struct(record) do
    with {:ok, module} <- lookup(slug),
         true <- function_exported?(module, :available_events, 1) do
      {:ok, module.available_events(record)}
    else
      :error -> {:error, :not_found}
      false -> {:error, :not_a_fosm_model}
    end
  end
  
  @doc """
  Checks if a model is registered.
  """
  @spec registered?(String.t()) :: boolean()
  def registered?(slug) when is_binary(slug) do
    :ets.member(@table, slug)
  end
  
  @doc """
  Auto-registers all FOSM models from the application configuration.
  
  This is called at application startup and registers models defined in:
  
      config :fosm, :models, [
        {"invoice", MyApp.Invoice},
        {"order", MyApp.Order}
      ]
  
  Also discovers models with `Fosm.Lifecycle` from specified modules.
  """
  @spec auto_register() :: :ok
  def auto_register do
    GenServer.call(__MODULE__, :auto_register)
  end
  
  # Server Callbacks
  
  @impl GenServer
  def init(_opts) do
    # Create public ETS table for concurrent reads
    # The GenServer owns the table but clients read directly from ETS
    table = :ets.new(@table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: false
    ])
    
    Logger.info("Fosm.Registry started with ETS table")
    
    {:ok, %{table: table}}
  end
  
  @impl GenServer
  def handle_call({:register, slug, module, opts}, _from, state) do
    meta = %{
      registered_at: DateTime.utc_now(),
      auto_register: Keyword.get(opts, :auto_register, false)
    }
    
    # Validate it's a FOSM model
    unless fosm_model?(module) do
      Logger.warning("Attempted to register non-FOSM module: #{inspect(module)}")
      {:reply, {:error, :not_a_fosm_model}, state}
    else
      :ets.insert(@table, {slug, module, meta})
      Logger.info("Registered FOSM model: #{slug} => #{inspect(module)}")
      {:reply, :ok, state}
    end
  end
  
  @impl GenServer
  def handle_call({:unregister, slug}, _from, state) do
    :ets.delete(@table, slug)
    Logger.info("Unregistered FOSM model: #{slug}")
    {:reply, :ok, state}
  end
  
  @impl GenServer
  def handle_call(:auto_register, _from, state) do
    # Register from config
    models = Application.get_env(:fosm, :models, [])
    
    registered = Enum.reduce(models, [], fn 
      {slug, module}, acc when is_binary(slug) and is_atom(module) ->
        case register(slug, module, auto_register: true) do
          :ok -> [slug | acc]
          {:error, _} -> acc
        end
        
      entry, acc ->
        Logger.warning("Invalid model registration entry: #{inspect(entry)}")
        acc
    end)
    
    # Auto-discover from configured modules
    discover_modules = Application.get_env(:fosm, :auto_discover_modules, [])
    discovered = discover_fosm_models(discover_modules)
    
    Logger.info("Auto-registered #{length(registered)} models from config, discovered #{length(discovered)} models")
    
    {:reply, :ok, state}
  end
  
  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  # Private functions
  
  defp fosm_model?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and 
      function_exported?(module, :fosm_lifecycle, 0)
  rescue
    _ -> false
  end
  
  defp discover_fosm_modules([]), do: []
  
  defp discover_fosm_models(modules) when is_list(modules) do
    Enum.flat_map(modules, fn module ->
      if Code.ensure_loaded?(module) do
        # Look for nested modules that use Fosm.Lifecycle
        module
        |> Module.split()
        |> find_fosm_modules()
      else
        []
      end
    end)
  end
  
  defp find_fosm_modules(module_prefix) do
    # This would scan modules under the given prefix
    # In practice, we rely on explicit configuration for now
    []
  end
end

# Additional error type for registry
defmodule Fosm.Errors.RegistryNotFound do
  @moduledoc """
  Raised when looking up a slug that is not registered.
  """
  defexception [:slug]

  @impl Exception
  def message(%{slug: slug}) do
    "No FOSM model registered for slug '#{slug}'"
  end
end
