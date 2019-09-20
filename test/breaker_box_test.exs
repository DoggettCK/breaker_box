defmodule BreakerBoxTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias BreakerBox
  alias BreakerConfiguration

  doctest BreakerBox

  @test_breaker_name "TestBreaker"
  @test_breaker_config %BreakerConfiguration{}
  @non_existent_breaker "NonExistentBreaker"

  setup_all do
    {:ok, _} = BreakerBox.start_link([])

    :ok
  end

  setup do
    BreakerBox.register(@test_breaker_name, @test_breaker_config)

    on_exit(fn ->
      BreakerBox.remove(@test_breaker_name)
      BreakerBox.remove(@non_existent_breaker)
    end)
  end

  describe "disable/1" do
    test "breaker is disabled if it exists" do
      assert {:ok, @test_breaker_name} = BreakerBox.status(@test_breaker_name)

      assert :ok = BreakerBox.disable(@test_breaker_name)

      assert {:error, {:breaker_tripped, @test_breaker_name}} =
               BreakerBox.status(@test_breaker_name)
    end

    test "fails to disable a breaker that isn't there" do
      assert {:error, {:breaker_not_found, @non_existent_breaker}} =
               BreakerBox.status(@non_existent_breaker)

      assert {:error, {:breaker_not_found, @non_existent_breaker}} =
               BreakerBox.disable(@non_existent_breaker)
    end
  end

  describe "enable/1" do
    test "breaker is enabled if it exists and is already enabled (noop)" do
      assert {:ok, @test_breaker_name} = BreakerBox.status(@test_breaker_name)

      assert :ok = BreakerBox.enable(@test_breaker_name)
    end

    test "breaker is enabled if it exists and was previously disabled" do
      assert {:ok, @test_breaker_name} = BreakerBox.status(@test_breaker_name)

      assert :ok = BreakerBox.disable(@test_breaker_name)

      assert {:error, {:breaker_tripped, @test_breaker_name}} =
               BreakerBox.status(@test_breaker_name)

      assert :ok = BreakerBox.enable(@test_breaker_name)

      assert {:ok, @test_breaker_name} = BreakerBox.status(@test_breaker_name)
    end

    test "fails to disable a breaker that isn't there" do
      assert {:error, {:breaker_not_found, @non_existent_breaker}} =
               BreakerBox.status(@non_existent_breaker)

      assert {:error, {:breaker_not_found, @non_existent_breaker}} =
               BreakerBox.enable(@non_existent_breaker)
    end
  end

  describe "register/2" do
    test "registers a breaker with the system" do
      assert {:error, {:breaker_not_found, @non_existent_breaker}} =
               BreakerBox.status(@non_existent_breaker)

      assert :ok = BreakerBox.register(@non_existent_breaker, @test_breaker_config)

      assert {:ok, @non_existent_breaker} = BreakerBox.status(@non_existent_breaker)

      expected_config = @test_breaker_config

      assert {:ok, ^expected_config} = BreakerBox.get_config(@non_existent_breaker)

      assert :ok = BreakerBox.remove(@non_existent_breaker)

      assert {:error, {:breaker_not_found, @non_existent_breaker}} =
               BreakerBox.status(@non_existent_breaker)
    end

    test "re-registering a breaker will override the original configuration" do
      assert {:error, {:breaker_not_found, @non_existent_breaker}} =
               BreakerBox.status(@non_existent_breaker)

      assert :ok = BreakerBox.register(@non_existent_breaker, @test_breaker_config)

      assert {:ok, @non_existent_breaker} = BreakerBox.status(@non_existent_breaker)

      expected_config = @test_breaker_config
      new_config = BreakerConfiguration.reset_after_milliseconds(@test_breaker_config, 999_999)

      assert {:ok, ^expected_config} = BreakerBox.get_config(@non_existent_breaker)

      assert :ok = BreakerBox.register(@non_existent_breaker, new_config)

      assert {:ok, @non_existent_breaker} = BreakerBox.status(@non_existent_breaker)

      assert {:ok, ^new_config} = BreakerBox.get_config(@non_existent_breaker)

      assert :ok = BreakerBox.remove(@non_existent_breaker)

      assert {:error, {:breaker_not_found, @non_existent_breaker}} =
               BreakerBox.status(@non_existent_breaker)
    end
  end

  describe "registered/0" do
    test "shows all breakers registered in the system" do
      assert is_map(BreakerBox.registered())

      assert BreakerBox.registered() |> Map.has_key?(@test_breaker_name)

      expected_config = @test_breaker_config

      assert ^expected_config = BreakerBox.registered() |> Map.get(@test_breaker_name)

      refute BreakerBox.registered() |> Map.has_key?(@non_existent_breaker)
    end
  end

  describe "reset/1" do
    test "resets a breaker that exists and is not blown (noop)" do
      assert {:ok, @test_breaker_name} = BreakerBox.status(@test_breaker_name)

      assert :ok = BreakerBox.reset(@test_breaker_name)
    end

    test "does not reset a breaker that doesn't exist" do
      assert {:error, {:breaker_not_found, @non_existent_breaker}} =
               BreakerBox.status(@non_existent_breaker)

      assert {:error, {:breaker_not_found, @non_existent_breaker}} =
               BreakerBox.reset(@non_existent_breaker)
    end

    test "does not reset a breaker that has been manually disabled" do
      assert {:ok, @test_breaker_name} = BreakerBox.status(@test_breaker_name)

      assert :ok = BreakerBox.disable(@test_breaker_name)

      assert {:error, {:breaker_tripped, @test_breaker_name}} =
               BreakerBox.status(@test_breaker_name)

      assert :ok = BreakerBox.reset(@test_breaker_name)

      assert {:error, {:breaker_tripped, @test_breaker_name}} =
               BreakerBox.status(@test_breaker_name)

      assert :ok = BreakerBox.enable(@test_breaker_name)

      assert {:ok, @test_breaker_name} = BreakerBox.status(@test_breaker_name)
    end

    test "resets a breaker that has been blown by exceeding the error limit" do
      {breaker_name, %BreakerConfiguration{max_failures: failures} = breaker_config} =
        StrictBreaker.registration()

      assert :ok = BreakerBox.register(breaker_name, breaker_config)

      1..failures
      |> Enum.each(fn _ ->
        assert {:ok, ^breaker_name} = BreakerBox.status(breaker_name)
        assert :ok = BreakerBox.increment_error(breaker_name)
      end)

      assert {:error, {:breaker_tripped, ^breaker_name}} = BreakerBox.status(breaker_name)

      assert :ok = BreakerBox.reset(breaker_name)

      assert {:ok, ^breaker_name} = BreakerBox.status(breaker_name)
    end
  end

  describe "status/0" do
    test "returns the status of all breakers in the system" do
      assert BreakerBox.status() |> Map.has_key?(@test_breaker_name)

      assert {:ok, @test_breaker_name} = BreakerBox.status() |> Map.get(@test_breaker_name)

      refute BreakerBox.status() |> Map.has_key?(@non_existent_breaker)
    end

    test "returns the correct status of all breakers" do
      assert :ok = BreakerBox.disable(@test_breaker_name)

      assert {:error, {:breaker_tripped, @test_breaker_name}} =
               BreakerBox.status(@test_breaker_name)

      assert BreakerBox.status() |> Map.has_key?(@test_breaker_name)

      assert {:error, {:breaker_tripped, @test_breaker_name}} =
               BreakerBox.status() |> Map.get(@test_breaker_name)

      assert :ok = BreakerBox.enable(@test_breaker_name)

      assert BreakerBox.status() |> Map.has_key?(@test_breaker_name)

      assert {:ok, @test_breaker_name} = BreakerBox.status() |> Map.get(@test_breaker_name)
    end
  end

  describe "status/1" do
    test "returns the status of a single breaker in the system" do
      assert {:ok, @test_breaker_name} = BreakerBox.status(@test_breaker_name)
    end

    test "returns the current status of a breaker" do
      assert {:ok, @test_breaker_name} = BreakerBox.status(@test_breaker_name)

      assert :ok = BreakerBox.disable(@test_breaker_name)

      assert {:error, {:breaker_tripped, @test_breaker_name}} =
               BreakerBox.status(@test_breaker_name)

      assert :ok = BreakerBox.enable(@test_breaker_name)

      assert {:ok, @test_breaker_name} = BreakerBox.status(@test_breaker_name)
    end

    test "errors if the breaker doesn't exist in the system" do
      assert {:error, {:breaker_not_found, @non_existent_breaker}} =
               BreakerBox.status(@non_existent_breaker)
    end
  end

  describe "init/1" do
    test "fails to add circuit breaker module if it is not a module" do
      expected_error_message =
        "BreakerBox: \"NonExistentBreaker\" failed to register " <>
          "via init/1 because it is not a module"

      assert capture_log(fn ->
               assert {:ok, %{}} = BreakerBox.init([@non_existent_breaker])
             end) =~ expected_error_message

      assert {:error, {:breaker_not_found, @non_existent_breaker}} =
               BreakerBox.status(@non_existent_breaker)

      expected_error_message =
        "BreakerBox: :some_atom failed to register " <>
          "via init/1 because it is not a module"

      assert capture_log(fn ->
               assert {:ok, %{}} = BreakerBox.init([:some_atom])
             end) =~ expected_error_message

      assert {:error, {:breaker_not_found, :some_atom}} = BreakerBox.status(:some_atom)
    end

    test "fails to add circuit breaker module if it does not implement behaviour" do
      expected_error_message =
        "BreakerBox: MisbehavingBreaker failed to register " <>
          "via init/1 because it does not implement " <>
          "BreakerConfiguration behaviour"

      assert capture_log(fn ->
               assert {:ok, %{}} = BreakerBox.init([MisbehavingBreaker])
             end) =~ expected_error_message

      assert {:error, {:breaker_not_found, MisbehavingBreaker}} =
               BreakerBox.status(MisbehavingBreaker)
    end

    test "initializes properly if circuit breaker module does implement behaviour" do
      assert {:ok, state} = BreakerBox.init([BehavingBreaker])

      breaker_name = BehavingBreaker.name()

      assert Map.has_key?(state, breaker_name)

      expected_config = BehavingBreaker.config()

      assert ^expected_config = Map.get(state, breaker_name)

      assert {:ok, ^breaker_name} = BreakerBox.status(breaker_name)

      assert :ok = BreakerBox.remove(breaker_name)

      assert {:error, {:breaker_not_found, ^breaker_name}} = BreakerBox.status(breaker_name)
    end
  end

  describe "increment_error/1" do
    test "trips a breaker if error limit is exceeded" do
      {breaker_name, %BreakerConfiguration{max_failures: failures} = breaker_config} =
        StrictBreaker.registration()

      assert :ok = BreakerBox.register(breaker_name, breaker_config)

      1..failures
      |> Enum.each(fn _ ->
        assert {:ok, ^breaker_name} = BreakerBox.status(breaker_name)
        assert :ok = BreakerBox.increment_error(breaker_name)
      end)

      assert {:error, {:breaker_tripped, ^breaker_name}} = BreakerBox.status(breaker_name)
    end

    test "does not trip a breaker if ignore_error is true" do
      {breaker_name, %BreakerConfiguration{max_failures: failures} = breaker_config} =
        StrictBreaker.registration()

      assert :ok = BreakerBox.register(breaker_name, breaker_config)

      1..(2 * failures)
      |> Enum.each(fn _ ->
        assert {:ok, ^breaker_name} = BreakerBox.status(breaker_name)
        assert :ok = BreakerBox.increment_error(breaker_name, ignore_error: true)
      end)

      assert {:ok, ^breaker_name} = BreakerBox.status(breaker_name)
    end
  end
end

defmodule MisbehavingBreaker do
  # Doesn't do anything, specifically doesn't implement
  # @behaviour BreakerConfiguration
end

defmodule BehavingBreaker do
  alias BreakerConfiguration

  @behaviour BreakerConfiguration

  @breaker_name "behaving_breaker"
  @breaker_config %BreakerConfiguration{}

  @impl true
  def registration do
    {@breaker_name, @breaker_config}
  end

  def name, do: @breaker_name
  def config, do: @breaker_config
end

defmodule StrictBreaker do
  alias BreakerConfiguration

  @behaviour BreakerConfiguration

  @breaker_name "strict_breaker"

  # Five errors in a minute should trip the breaker, resetting after an hour,
  # to avoid race conditions
  @breaker_config %BreakerConfiguration{}
                  |> BreakerConfiguration.trip_on_failure_number(5)
                  |> BreakerConfiguration.within_minutes(1)
                  |> BreakerConfiguration.reset_after_minutes(60)

  @impl true
  def registration do
    {@breaker_name, @breaker_config}
  end

  def name, do: @breaker_name
  def config, do: @breaker_config
end
