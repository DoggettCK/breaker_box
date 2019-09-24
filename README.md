kerBox

[![Hex Version][hex-img]][hex] [![Hex Downloads][downloads-img]][downloads] [![License][license-img]][license]

[hex-img]: https://img.shields.io/hexpm/v/breaker_box.svg
[hex]: https://hex.pm/packages/breaker_box
[downloads-img]: https://img.shields.io/hexpm/dt/breaker_box.svg
[downloads]: https://hex.pm/packages/breaker_box
[license-img]: https://img.shields.io/badge/license-MIT-blue.svg
[license]: https://opensource.org/licenses/MIT

## Description

`BreakerBox` is an implementation of the [circuit breaker pattern]([https://www.martinfowler.com/bliki/CircuitBreaker.html](https://www.martinfowler.com/bliki/CircuitBreaker.html)), wrapping the [Fuse](https://github.com/jlouis/fuse) Erlang library with a supervised server for ease of breaker configuration and management.

## Examples
### Breaker configuration
```elixir
breaker_config =
 %BreakerConfiguration{}
 |> BreakerConfiguration.trip_on_failure_number(5)
 |> BreakerConfiguration.within_minutes(1)
 |> BreakerConfiguration.reset_after_minutes(1)
```

`BreakerBox` is intended to be user-friendly for configuration, wrapping [Fuse's](https://github.com/jlouis/fuse) options in a way that's easier to understand.

For example, Fuse's configuration allows you to set the number of errors ***tolerated*** in a given time window, but in testing, developers found that confusing, as they expected the breaker to be tripped after the `N`th error was encountered, only to find that it actually tripped on error `N+1`. This means that behind the scenes, `BreakerBox` is telling `Fuse` to tolerate `N-1` errors.

Both `within_*` and `after_*` methods have variants accepting minutes, seconds, or milliseconds.

A default `%BreakerConfiguration{}` will trip on the 5th failure within 1 second, automatically resetting to untripped after 5 seconds.

### Registering a breaker manually
```elixir
BreakerBox.register("BreakerName", breaker_config)
```

Breakers must be registered with a unique name and configuration. Re-registering a breaker with the same name will overwrite the existing breaker.

Names can be strings, atoms, or for ease of use in automatic registration, module names.

### Registering a breaker automatically
`BreakerBox` is designed to be used with Elixir's supervision system, so we've provided a way to automatically register breakers at application startup, provided they implement a [Behaviour]([https://elixir-lang.org/getting-started/typespecs-and-behaviours.html#behaviours](https://elixir-lang.org/getting-started/typespecs-and-behaviours.html#behaviours)) from `BreakerConfiguration`.

```elixir
# breaker_one.ex
defmodule BreakerOne do
  @behaviour BreakerConfiguration

  @impl true
  def registration do
    # Fail after 3rd error in one minute, resetting after a minute
    breaker_config =
      %BreakerConfiguration{}
      |> BreakerConfiguration.trip_on_failure_number(3)
      |> BreakerConfiguration.within_minutes(1)
      |> BreakerConfiguration.reset_after_minutes(1)

    {__MODULE__, breaker_config}
  end
end

# application.ex
defmodule YourApplication do
  use Application

  @circuit_breaker_modules [
    BreakerOne
  ]

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(Repo, []),
      worker(BreakerBox, [@circuit_breaker_modules])
    ]

    opts = [strategy: :one_for_one, name: Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

This will register the breaker using the module's own name as the breaker name, though as mentioned earlier, you can use whatever you want. `BreakerBox` uses the [Behave](https://hex.pm/packages/behave) package to ensure that whatever modules you pass in for automatic registration implement the `BreakerConfiguration` behaviour, warning you via `Logger` messages at startup if anything is misconfigured.

### View registered breakers
```elixir
iex> BreakerBox.registered
%{
  BreakerOne => %BreakerConfiguration{
    failure_window: 60000,
    max_failures: 3,
    reset_window: 60000
  },
  BreakerTwo => %BreakerConfiguration{
    failure_window: 60000,
    max_failures: 5,
    reset_window: 30000
  }
}
```

### View breaker status(es)
```elixir
# View status of all breakers
iex> BreakerBox.status()
%{BreakerOne => {:ok, BreakerOne}, BreakerTwo => {:ok, BreakerTwo}}

# View status of a particular breaker
iex> BreakerBox.status(BreakerOne)
{:ok, BreakerOne}
```

Status of a breaker will be returned as one of:

 - `{:ok, breaker_name}`
 - `{:error, {:breaker_tripped, breaker_name}}`
 - `{:error, {:breaker_not_found, breaker_name}}`

## Installation

`BreakerBox` can be installed by adding `breaker_box` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:breaker_box, "~> 0.1.0"}
  ]
end
```

## Documentation

Documentation can be found at [https://hexdocs.pm/breaker_box](https://hexdocs.pm/breaker_box).
