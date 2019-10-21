defmodule BreakerBox.BreakerConfiguration do
  @moduledoc """
  Structure and behaviour for configuring circuit breakers.
  """
  alias __MODULE__

  @default_max_failures 5
  @default_failure_window 1_000
  @default_reset_window 5_000

  defstruct max_failures: @default_max_failures,
            failure_window: @default_failure_window,
            reset_window: @default_reset_window

  @typedoc """
  Options for controlling circuit breaker behavior.

  Defaults were chosen from external_service/fuse examples, and are open to
  change. By default, breakers will trip on the 5th failure within 1 second,
  resetting automatically after 5 seconds.

  ## Defaults
  | **Field** | **Value** |
  | max_failures | 5 |
  | failure_window | 1_000 |
  | reset_window | 5_000 |
  """
  @type t() :: %__MODULE__{
          max_failures: pos_integer(),
          failure_window: pos_integer(),
          reset_window: pos_integer()
        }

  @doc """
  Retrieve the name and configuration map of a circuit breaker.

  Called by `BreakerBox.start_link/1` on every module passed in from
  `Application.start`.

  Implementations should return a 2-tuple containing the name of the breaker
  and the `BreakerBox.BreakerConfiguration` options for registering the
  breaker.

  This is only required and useful for breakers that should be automatically
  registered at startup. You can still manually call `BreakerBox.register/2` if
  you don't need to make use of supervision.

  \\__MODULE__ is a good default breaker name, but can be a string, atom, or
  anything you want. Re-using a breaker name in multiple places will overwrite
  with the last configuration.

  ```
  @impl true
  def registration do
    breaker_config =
      %BreakerBox.BreakerConfiguration{}
      |> BreakerBox.BreakerConfiguration.trip_on_failure_number(10) # Trip after 10th failure
      |> BreakerBox.BreakerConfiguration.within_seconds(1) # within 1 second
      |> BreakerBox.BreakerConfiguration.reset_after_seconds(5) # Automatically reset breaker after 5s

    {__MODULE__, breaker_config}
  end
  ```
  """
  @callback registration() :: {breaker_name :: term, breaker_config :: BreakerConfiguration.t()}

  defguardp is_positive_integer(i) when is_integer(i) and i > 0

  @doc """
  Converts our `BreakerBox.BreakerConfiguration` struct type to the format Fuse
  expects.

  NOTE: The underlying Fuse library treats maximum failures as the number of
  errors per time window the breaker can *tolerate*, which can lead to some
  confusion. If you're setting the breaker expecting it to fail after 5 errors
  in one second, you may be surprised that it doesn't actually trip until the
  6th error in the same time window. This package's API tries to account for
  that by insisting `max_failures` be greater than zero, so we can always
  subtract one, and `trip_on_failure_number` will behave as a user would
  expect.
  """
  @spec to_fuse_options(config :: BreakerConfiguration.t()) ::
          {{:standard, pos_integer, pos_integer}, {:reset, pos_integer}}
  def to_fuse_options(%BreakerConfiguration{} = config) do
    {
      {:standard, max(config.max_failures - 1, 1), config.failure_window},
      {:reset, config.reset_window}
    }
  end

  @doc """
  Configure a breaker to trip on the Nth failure within the configured
  `failure_window`.

  The underlying Fuse library *tolerates* N failures before tripping the
  breaker on failure N+1. We've gone with the more user-friendly behaviour of
  having it trip *after* N errors by telling Fuse to tolerate N-1 errors.

  NOTE: Fuse insists on tolerating *at least* 1 error, so unfortunately it
  can't be configured to trip on the first error, and will use the default
  value of #{@default_max_failures} if a value less than or equal to 1 is used,
  or a non-integer.
  """
  @spec trip_on_failure_number(config :: BreakerConfiguration.t(), max_failures :: pos_integer) ::
          BreakerConfiguration.t()
  def trip_on_failure_number(%BreakerConfiguration{} = config, max_failures)
      when is_positive_integer(max_failures) and max_failures > 1 do
    %BreakerConfiguration{config | max_failures: max_failures}
  end

  def trip_on_failure_number(%BreakerConfiguration{} = config, _max_failures) do
    %BreakerConfiguration{config | max_failures: @default_max_failures}
  end

  @doc """
  Configure a breaker's failure window using milliseconds.

  Breaker will trip on Nth error within `failure_window` milliseconds.

  If attempted to set with a non-positive-integer value, it will use the
  default value of #{@default_failure_window}
  """
  @spec within_milliseconds(config :: BreakerConfiguration.t(), failure_window :: pos_integer) ::
          BreakerConfiguration.t()
  def within_milliseconds(%BreakerConfiguration{} = config, failure_window)
      when is_positive_integer(failure_window) do
    %BreakerConfiguration{config | failure_window: failure_window}
  end

  def within_milliseconds(%BreakerConfiguration{} = config, _failure_window) do
    %BreakerConfiguration{config | failure_window: @default_failure_window}
  end

  @doc """
  Configure a breaker's failure window using minutes.

  Breaker will trip on Nth error within `failure_window` * 60 seconds * 1000 milliseconds.

  If attempted to set with a non-positive-integer value, it will use the
  default value of #{@default_failure_window} milliseconds.
  """
  @spec within_minutes(config :: BreakerConfiguration.t(), failure_window :: pos_integer) ::
          BreakerConfiguration.t()
  def within_minutes(%BreakerConfiguration{} = config, failure_window)
      when is_positive_integer(failure_window) do
    %BreakerConfiguration{config | failure_window: failure_window * 60 * 1_000}
  end

  def within_minutes(%BreakerConfiguration{} = config, _failure_window) do
    %BreakerConfiguration{config | failure_window: @default_failure_window}
  end

  @doc """
  Configure a breaker's failure window using seconds.

  Breaker will trip on Nth error within `failure_window` * 1000 milliseconds.

  If attempted to set with a non-positive-integer value, it will use the
  default value of #{@default_failure_window} milliseconds.
  """
  @spec within_seconds(config :: BreakerConfiguration.t(), failure_window :: pos_integer) ::
          BreakerConfiguration.t()
  def within_seconds(%BreakerConfiguration{} = config, failure_window)
      when is_positive_integer(failure_window) do
    %BreakerConfiguration{config | failure_window: failure_window * 1_000}
  end

  def within_seconds(%BreakerConfiguration{} = config, _failure_window) do
    %BreakerConfiguration{config | failure_window: @default_failure_window}
  end

  @doc """
  Configure a breaker's reset window using minutes.

  A tripped breaker that hasn't been manually disabled will automatically reset
  to untripped after `reset_window` * 60 seconds * 1000 milliseconds.

  If attempted to set with a non-positive-integer value, it will use the
  default value of #{@default_reset_window} milliseconds.
  """
  @spec reset_after_minutes(config :: BreakerConfiguration.t(), reset_window :: pos_integer) ::
          BreakerConfiguration.t()
  def reset_after_minutes(%BreakerConfiguration{} = config, reset_window)
      when is_positive_integer(reset_window) do
    %BreakerConfiguration{config | reset_window: reset_window * 60 * 1_000}
  end

  def reset_after_minutes(%BreakerConfiguration{} = config, _reset_window) do
    %BreakerConfiguration{config | reset_window: @default_reset_window}
  end

  @doc """
  Configure a breaker's reset window using seconds.

  A tripped breaker that hasn't been manually disabled will automatically reset
  to untripped after `reset_window` * 1000 milliseconds.

  If attempted to set with a non-positive-integer value, it will use the
  default value of #{@default_reset_window} milliseconds.
  """
  @spec reset_after_seconds(config :: BreakerConfiguration.t(), reset_window :: pos_integer) ::
          BreakerConfiguration.t()
  def reset_after_seconds(%BreakerConfiguration{} = config, reset_window)
      when is_positive_integer(reset_window) do
    %BreakerConfiguration{config | reset_window: reset_window * 1_000}
  end

  def reset_after_seconds(%BreakerConfiguration{} = config, _reset_window) do
    %BreakerConfiguration{config | reset_window: @default_reset_window}
  end

  @doc """
  Configure a breaker's reset window using milliseconds.

  A tripped breaker that hasn't been manually disabled will automatically reset
  to untripped after `reset_window` milliseconds.

  If attempted to set with a non-positive-integer value, it will use the
  default value of #{@default_reset_window} milliseconds.
  """
  @spec reset_after_milliseconds(config :: BreakerConfiguration.t(), reset_window :: pos_integer) ::
          BreakerConfiguration.t()
  def reset_after_milliseconds(%BreakerConfiguration{} = config, reset_window)
      when is_positive_integer(reset_window) do
    %BreakerConfiguration{config | reset_window: reset_window}
  end

  def reset_after_milliseconds(%BreakerConfiguration{} = config, _reset_window) do
    %BreakerConfiguration{config | reset_window: @default_reset_window}
  end

  @doc """
  Get a friendlier representation of the breaker configuration.

  ## Examples
      iex> %BreakerBox.BreakerConfiguration{} |> BreakerBox.BreakerConfiguration.human_readable()
      "Trip on 5th error within 1000ms, resetting after 5000ms."
  """
  @spec human_readable(configuration :: BreakerConfiguration.t()) :: String.t()
  def human_readable(%BreakerConfiguration{} = configuration) do
    %{
      max_failures: max_failures,
      failure_window: failure_window,
      reset_window: reset_window
    } = configuration

    "Trip on #{ordinalize(max_failures)} error within #{failure_window}ms, resetting after #{
      reset_window
    }ms."
  end

  defp ordinalize(number) when is_integer(number) and number >= 0 do
    suffix =
      if Enum.member?([11, 12, 13], rem(number, 100)) do
        "th"
      else
        case rem(number, 10) do
          1 -> "st"
          2 -> "nd"
          3 -> "rd"
          _ -> "th"
        end
      end

    "#{number}#{suffix}"
  end

  defp ordinalize(number), do: number
end
