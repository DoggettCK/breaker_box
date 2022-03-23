defmodule BreakerBox do
  @moduledoc """
  Server for circuit breakers.

  Maintains state of registered breakers and their configurations, and allows
  for querying the status of breakers, as well as enabling and disabling.

  Modules can be automatically registered if they implement the
  `BreakerBox.BreakerConfiguration` behaviour and are passed in to `start_link/2`.
  """
  use GenServer

  require Behave
  require Logger

  alias :fuse, as: Fuse
  alias BreakerBox.BreakerConfiguration

  @typep fuse_status ::
           {:ok, breaker_name :: term}
           | {:error, {:breaker_tripped, breaker_name :: term}}
           | {:error, {:breaker_not_found, breaker_name :: term}}
  @typep ok_or_not_found :: :ok | {:error, {:breaker_not_found, breaker_name :: term}}

  ### PUBLIC API
  @doc """
  Wrapper around `GenServer.start_link/3`. Passes the list of modules received
  to `init/1`, which will attempt to register the circuit breakers inside those
  modules.

  Modules passed in are expected to implement the `BreakerBox.BreakerConfiguration`
  behaviour via `@behaviour BreakerBox.BreakerConfiguration`, which will require them to
  have a method named `registration/0` that returns a 2-tuple containing the
  breaker's name and configuration options.
  """
  @spec start_link(circuit_breaker_modules :: list(module), process_name :: term) ::
          {:ok, pid}
          | {:error, {:already_started, pid}}
          | {:error, reason :: term}
          | {:stop, reason :: term}
          | :ignore
  def start_link(circuit_breaker_modules, process_name \\ __MODULE__) do
    GenServer.start_link(__MODULE__, circuit_breaker_modules, name: process_name)
  end

  @doc """
  Initializes the breaker box state, attempting to call `registration/0` on
  every argument passed in, assuming they're a module implementing the
  `BreakerBox.BreakerConfiguration` behaviour. If they are not a module, or don't
  implement the behaviour, a warning will be logged indicating how to fix the
  issue, and that item will be skipped.
  """
  @spec init(circuit_breaker_modules :: list(module)) ::
          {:ok, %{optional(term) => BreakerConfiguration.t()}}
  def init(circuit_breaker_modules) do
    state = Enum.reduce(circuit_breaker_modules, %{}, &register_or_warn/2)

    {:ok, state}
  end

  @doc """
  Register a circuit breaker given its name and options.

  \\__MODULE__ is a good default breaker name, but can be a string, atom, or
  anything you want. Re-using a breaker name in multiple places will overwrite
  with the last configuration.
  """
  @spec register(
          breaker_name :: term,
          breaker_options :: BreakerConfiguration.t(),
          process_name :: term
        ) ::
          :ok | :reset | {:error, reason :: term}
  def register(breaker_name, breaker_options, process_name \\ __MODULE__)

  # def register(_breaker_name, %BreakerConfiguration{max_failures: max_failures}, _process_name)
  # when max_failures <= 1 do
  # {:error, "BreakerBox: max_failures must be greater than 1"}
  # end

  def register(
        breaker_name,
        %BreakerConfiguration{} = breaker_options,
        process_name
      ) do
    GenServer.call(process_name, {:register, breaker_name, breaker_options})
  end

  @doc """
  Remove a circuit breaker.
  """
  @spec remove(breaker_name :: term, process_name :: term) :: ok_or_not_found
  def remove(breaker_name, process_name \\ __MODULE__) do
    GenServer.call(process_name, {:remove, breaker_name})
  end

  @doc """
  Retrieve the configuration for a breaker.
  """
  @spec get_config(breaker_name :: term, process_name :: term) ::
          {:ok, BreakerConfiguration.t()} | {:error, :not_found}
  def get_config(breaker_name, process_name \\ __MODULE__) do
    GenServer.call(process_name, {:get_config, breaker_name})
  end

  @doc """
  Retrieve a map with breaker names as keys and
  `BreakerBox.BreakerConfiguration` structs as values.
  """
  @spec registered(process_name :: term) :: %{optional(term) => BreakerConfiguration.t()}
  def registered(process_name \\ __MODULE__) do
    GenServer.call(process_name, :registered)
  end

  @doc """
  Retrieve the status of a single breaker.
  """
  @spec status(breaker_name :: term, process_name :: term) :: fuse_status()
  def status(breaker_name, process_name \\ __MODULE__) do
    GenServer.call(process_name, {:status, breaker_name})
  end

  @doc """
  Retrieve the current status of all registered breakers.
  """
  @spec all_statuses(process_name :: term) :: %{optional(term) => fuse_status()}
  def all_statuses(process_name \\ __MODULE__) do
    GenServer.call(process_name, :status)
  end

  @doc """
  Reset a breaker that has been tripped. This will only reset breakers that
  have been blown via exceeding the error limit in a given time window, and
  will not re-enable a breaker that has been disabled via `disable/1`.
  """
  @spec reset(breaker_name :: term, process_name :: term) :: ok_or_not_found()
  def reset(breaker_name, process_name \\ __MODULE__) do
    GenServer.call(process_name, {:reset, breaker_name})
  end

  @doc """
  Disable a circuit breaker.

  Sets the breaker's status to `:breaker_tripped` until `enable/1` is called for the same
  breaker, or the application is restarted.

  Will not be reset by calling `reset/1`.
  """
  @spec disable(breaker_name :: term, process_name :: term) :: :ok
  def disable(breaker_name, process_name \\ __MODULE__) do
    GenServer.call(process_name, {:disable, breaker_name})
  end

  @doc """
  Enable a circuit breaker.

  Sets the breaker's status to `:ok`.
  """
  @spec enable(breaker_name :: term, process_name :: term) :: :ok
  def enable(breaker_name, process_name \\ __MODULE__) do
    GenServer.call(process_name, {:enable, breaker_name})
  end

  @doc """
  Increment the error counter for a circuit breaker.

  If this causes the breaker to go over its error limit for its time window,
  the breaker will trip, and subsequent calls to `status/1` will show it as
  `{:error, {:breaker_tripped, breaker_name}}`.
  """
  @spec increment_error(breaker_name :: term, process_name :: term) :: :ok
  def increment_error(breaker_name, process_name \\ __MODULE__) do
    GenServer.call(process_name, {:increment_error, breaker_name})
  end

  ### PRIVATE API
  defp fully_qualified_breaker_name(breaker_name) do
    self()
    |> Process.info()
    |> get_in([:registered_name])
    |> Module.concat(breaker_name)
  end

  def handle_call(
        {:register, breaker_name, %BreakerConfiguration{} = options},
        _from,
        state
      ) do
    {result, new_state} = register_breaker(breaker_name, options, state)

    {:reply, result, new_state}
  end

  def handle_call({:remove, breaker_name}, _from, state) do
    result =
      case breaker_status(breaker_name) do
        {:error, {:breaker_not_found, ^breaker_name}} = not_found ->
          not_found

        _ ->
          breaker_name
          |> fully_qualified_breaker_name()
          |> Fuse.remove()
      end

    {:reply, result, Map.delete(state, breaker_name)}
  end

  def handle_call({:get_config, breaker_name}, _from, state) do
    result =
      case Map.fetch(state, breaker_name) do
        :error ->
          {:error, :not_found}

        ok_tuple ->
          ok_tuple
      end

    {:reply, result, state}
  end

  def handle_call(:registered, _from, state) do
    registered_breakers =
      Enum.into(state, %{}, fn {breaker_name, breaker_options} ->
        {breaker_name, fuse_options_to_breaker_configuration(breaker_options)}
      end)

    {:reply, registered_breakers, state}
  end

  def handle_call({:status, breaker_name}, _from, state) do
    {:reply, breaker_status(breaker_name), state}
  end

  def handle_call(:status, _from, state) do
    all_statuses =
      Enum.into(state, %{}, fn {breaker_name, _} ->
        {breaker_name, breaker_status(breaker_name)}
      end)

    {:reply, all_statuses, state}
  end

  def handle_call({:reset, breaker_name}, _from, state) do
    result =
      case breaker_status(breaker_name) do
        {:error, {:breaker_not_found, ^breaker_name}} = not_found ->
          not_found

        _ ->
          breaker_name
          |> fully_qualified_breaker_name()
          |> Fuse.reset()
      end

    {:reply, result, state}
  end

  def handle_call({:disable, breaker_name}, _from, state) do
    result =
      case breaker_status(breaker_name) do
        {:error, {:breaker_not_found, ^breaker_name}} = not_found ->
          not_found

        _ ->
          breaker_name
          |> fully_qualified_breaker_name()
          |> Fuse.circuit_disable()
      end

    {:reply, result, state}
  end

  def handle_call({:enable, breaker_name}, _from, state) do
    result =
      case breaker_status(breaker_name) do
        {:error, {:breaker_not_found, ^breaker_name}} = not_found ->
          not_found

        _ ->
          breaker_name
          |> fully_qualified_breaker_name()
          |> Fuse.circuit_enable()
      end

    {:reply, result, state}
  end

  def handle_call({:increment_error, breaker_name}, _from, state) do
    result =
      case breaker_status(breaker_name) do
        {:error, {:breaker_not_found, ^breaker_name}} = not_found ->
          not_found

        _status ->
          breaker_name
          |> fully_qualified_breaker_name()
          |> Fuse.melt()
      end

    {:reply, result, state}
  end

  defp fuse_options_to_breaker_configuration(
         {{:standard, maximum_failures, failure_window}, {:reset, reset_window}}
       ) do
    %BreakerConfiguration{}
    |> BreakerConfiguration.trip_on_failure_number(maximum_failures)
    |> BreakerConfiguration.within_milliseconds(failure_window)
    |> BreakerConfiguration.reset_after_milliseconds(reset_window)
  end

  defp fuse_options_to_breaker_configuration(%BreakerConfiguration{} = config), do: config

  defp register_or_warn(breaker_module, state) do
    case Behave.behaviour_implemented?(breaker_module, BreakerConfiguration) do
      {:error, :not_a_module, ^breaker_module} ->
        breaker_module
        |> non_module_warning
        |> Logger.warn()

        state

      {:error, :behaviour_not_implemented} ->
        breaker_module
        |> missing_behaviour_warning
        |> Logger.warn()

        state

      :ok ->
        {breaker_name, breaker_options} = breaker_module.registration()

        {_, new_state} = register_breaker(breaker_name, breaker_options, state)

        new_state
    end
  end

  defp register_breaker(breaker_name, %BreakerConfiguration{} = breaker_options, state) do
    fuse_options = BreakerConfiguration.to_fuse_options(breaker_options)

    result =
      breaker_name
      |> fully_qualified_breaker_name()
      |> Fuse.install(fuse_options)

    new_state = Map.put(state, breaker_name, breaker_options)

    {result, new_state}
  end

  defp breaker_status(breaker_name) do
    fully_qualified_breaker_name = fully_qualified_breaker_name(breaker_name)

    case Fuse.ask(fully_qualified_breaker_name, :sync) do
      :ok -> {:ok, breaker_name}
      :blown -> {:error, {:breaker_tripped, breaker_name}}
      {:error, :not_found} -> {:error, {:breaker_not_found, breaker_name}}
    end
  end

  ### Error/Warning messages
  defp non_module_warning(breaker_module) do
    breaker_module
    |> registration_failure_warning("it is not a module")
  end

  defp missing_behaviour_warning(breaker_module) do
    breaker_module
    |> registration_failure_warning(
      "it does not implement #{inspect(BreakerConfiguration)} behaviour"
    )
  end

  defp registration_failure_warning(breaker_module, reason) do
    "BreakerBox: #{inspect(breaker_module)} failed to register via init/1 because " <> reason
  end
end
