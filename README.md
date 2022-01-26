# BreakerBox

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
 %BreakerBox.BreakerConfiguration{}
 |> BreakerBox.BreakerConfiguration.trip_on_failure_number(5)
 |> BreakerBox.BreakerConfiguration.within_minutes(1)
 |> BreakerBox.BreakerConfiguration.reset_after_minutes(1)
```

`BreakerBox` is intended to be user-friendly for configuration, wrapping [Fuse's](https://github.com/jlouis/fuse) options in a way that's easier to understand.

For example, Fuse's configuration allows you to set the number of errors ***tolerated*** in a given time window, but in testing, developers found that confusing, as they expected the breaker to be tripped after the `N`th error was encountered, only to find that it actually tripped on error `N+1`. This means that behind the scenes, `BreakerBox` is telling `Fuse` to tolerate `N-1` errors.

Both `within_*` and `after_*` methods have variants accepting minutes, seconds, or milliseconds.

A default `%BreakerBox.BreakerConfiguration{}` will trip on the 5th failure within 1 second, automatically resetting to untripped after 5 seconds.

Due to a limitation of the underlying Fuse library, BreakerBox is unable to trip on the first error, so any calls to `trip_on_failure_number/2` must fail on at least the second error.

### Registering a breaker manually
```elixir
BreakerBox.register("BreakerName", breaker_config)
```

Breakers must be registered with a unique name and configuration. Re-registering a breaker with the same name will overwrite the existing breaker.

Names can be strings, atoms, or for ease of use in automatic registration, module names.

### Registering a breaker automatically
`BreakerBox` is designed to be used with Elixir's supervision system, so we've provided a way to automatically register breakers at application startup, provided they implement a [Behaviour]([https://elixir-lang.org/getting-started/typespecs-and-behaviours.html#behaviours](https://elixir-lang.org/getting-started/typespecs-and-behaviours.html#behaviours)) from `BreakerBox.BreakerConfiguration`.

```elixir
# breaker_one.ex
defmodule BreakerOne do
  @behaviour BreakerBox.BreakerConfiguration

  @impl true
  def registration do
    # Fail after 3rd error in one minute, resetting after a minute
    breaker_config =
      %BreakerBox.BreakerConfiguration{}
      |> BreakerBox.BreakerConfiguration.trip_on_failure_number(3)
      |> BreakerBox.BreakerConfiguration.within_minutes(1)
      |> BreakerBox.BreakerConfiguration.reset_after_minutes(1)

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

This will register the breaker using the module's own name as the breaker name, though as mentioned earlier, you can use whatever you want. `BreakerBox` uses the [Behave](https://hex.pm/packages/behave) package to ensure that whatever modules you pass in for automatic registration implement the `BreakerBox.BreakerConfiguration` behaviour, warning you via `Logger` messages at startup if anything is misconfigured.

### View registered breakers
```elixir
iex> BreakerBox.registered
%{
  BreakerOne => %BreakerBox.BreakerConfiguration{
    failure_window: 60000,
    max_failures: 3,
    reset_window: 60000
  },
  BreakerTwo => %BreakerBox.BreakerConfiguration{
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

### Tell a breaker there has been an error
Now that you have your breakers set up, how do you let them know there's a problem?
```elixir
BreakerBox.increment_error(breaker_name)
```

Unless your breaker has been set up to be super-sensitive, one error probably won't trip it.
```elixir
iex> Breaker.increment_error(BreakerOne)
:ok
iex> BreakerBox.status(BreakerOne)
{:ok, BreakerOne}
iex> 1..10 |> Enum.each(fn _ -> BreakerBox.increment_error(BreakerOne) end)
:ok
iex> BreakerBox.status(BreakerOne)
{:error, {:breaker_tripped, BreakerOne}}

# Wait 60 seconds or call BreakerBox.reset(BreakerOne)
iex> BreakerBox.status(BreakerOne)
{:ok, BreakerOne}
```

### Manually enabling/disabling/resetting a breaker
By default, breakers that have been tripped will reset to untripped after the `reset_window` specified in your configuration. If you want to reset it sooner, for example in a test scenario, you can call `BreakerBox.reset(breaker_name)` to set it back to untripped.

What if you know a particular external service is going to be down for awhile, and want to disable all traffic to it?
```elixir
iex> BreakerBox.disable(BreakerOne)
:ok
iex> BreakerBox.status()
%{
  BreakerOne => {:error, {:breaker_tripped, BreakerOne}},
  BreakerTwo => {:ok, BreakerTwo}
}

# Wait as long as you want, it won't automatically reset
iex> BreakerBox.status(BreakerOne)
{:error, {:breaker_tripped, BreakerOne}}
```

Re-enabling it when you know or suspect the service is available again is just as simple.
```elixir
iex> BreakerBox.enable(BreakerOne)
:ok
iex> BreakerBox.status()
%{
  BreakerOne => {:ok, BreakerOne},
  BreakerTwo => {:ok, BreakerTwo}
}
```

### More than one breaker box

If you have a need for more than one set of circuit breakers, and don't want any overlap, for example, if you want to run tests that may interfere with each other in parallel, you can specify a `process_name` when calling `BreakerBox`, as of version 0.4.0, which will default to the module name `BreakerBox`.

```elixir
iex> BreakerBox.start_link([])
{:ok, #PID<0.233.0>}
iex> BreakerBox.start_link([], :OtherPanel)
{:ok, #PID<0.236.0>}
iex> BreakerBox.register("Breaker1", %BreakerBox.BreakerConfiguration{})
:ok
iex> BreakerBox.register("OtherPanelBreaker", %BreakerBox.BreakerConfiguration{}, :OtherPanel)
:ok
iex> BreakerBox.registered
%{
  "Breaker1" => %BreakerBox.BreakerConfiguration{
    failure_window: 1000,
    max_failures: 5,
    reset_window: 5000
  }
}
iex> BreakerBox.registered(:OtherPanel)
%{
  "OtherPanelBreaker" => %BreakerBox.BreakerConfiguration{
    failure_window: 1000,
    max_failures: 5,
    reset_window: 5000
  }
}
iex> BreakerBox.status("Breaker1")
{:ok, "Breaker1"}
iex> BreakerBox.status("Breaker1", :OtherPanel)
{:error, {:breaker_not_found, "Breaker1"}}
iex> BreakerBox.status("OtherBreaker")         
{:error, {:breaker_not_found, "OtherBreaker"}}
iex> BreakerBox.status("OtherBreaker", :OtherPanel)
{:ok, "OtherBreaker"}
```

Behind the scenes, `Module.concat/2` is used to make a unique name for the breaker name for the underlying Fuse library, since otherwise it would allow the same name in two different breaker boxes to overwrite each other.

### Tying it all together
In this example, we're going to POST a request to an external service at `url`. If we get a valid `HTTPoison` response back in an `{:ok, response}` tuple, we'll return the response body to the caller, no matter what it was, but if it wasn't a `200 OK`, we'll tell the breaker there was an error. You may not want to be this strict if you're using a `GET` request with a `301 Moved Permanently` response, but for my usual use case, a non-200 means something bad's happening.

If we specifically get an `HTTPoison.Error` struct back, usually in cases of a timeout or non-existent domain, increment the error there, too. If we got back that the breaker has already been tripped, we don't increment it again, but instead just pass back the error to be handled in the controller or fallback controller, where we'll typically create a `503 Service Unavailable` response to tell consumers of our API to try again later. Lastly, any other unexpected errors increment the error count and return.

We just want to ensure specifically that we're not incrementing again when the breaker is already tripped, as we haven't actually made the call to the external service.

```elixir
{breaker_name, _} = BreakerOne.registration()

with {:ok, ^breaker_name} <- BreakerBox.status(breaker_name),
     {:ok, response} <- HTTPoison.post(url, body, headers, options) do
  if response.status_code != 200 do
    BreakerBox.increment_error(breaker_name)
  end

  {:ok, response.body}
else
  {:error, %HTTPoison.Error{}} = error ->
    BreakerBox.increment_error(breaker_name)
    error

  {:error, {:breaker_tripped, ^breaker_name}} = error ->
    error

  other ->
    BreakerBox.increment_error(breaker_name)
    other
end
```

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
