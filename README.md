# BreakerBox

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `breaker_box` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:breaker_box, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/breaker_box](https://hexdocs.pm/breaker_box).
## OLD
# DeepGet

[![Hex Version][hex-img]][hex] [![Hex Downloads][downloads-img]][downloads] [![License][license-img]][license]

[hex-img]: https://img.shields.io/hexpm/v/deep_get.svg
[hex]: https://hex.pm/packages/deep_get
[downloads-img]: https://img.shields.io/hexpm/dt/deep_get.svg
[downloads]: https://hex.pm/packages/deep_get
[license-img]: https://img.shields.io/badge/license-MIT-blue.svg
[license]: https://opensource.org/licenses/MIT

## Description

`DeepGet` allows you to take an object (map/struct/list/keyword list) or list
of them, nested to an arbitrary level, and extract the values corresponding to
a list of keys.

Lets say you had a Map of a Company with a list of Managers, each of whom has
many Employees, each of whom has one or more phone numbers, and you wanted to
get the phone numbers of every employee from the map.

Traditionally, you'd have to do something like:

```elixir
phone_numbers =
  company
  |> Enum.map(fn company -> Map.get(company, :managers) end)
  |> Enum.map(fn manager -> Map.get(manager, :employees) end)
  |> Enum.map(fn employee -> Map.get(employee, :phone_numbers) end)
  |> List.flatten()
```

What happens if any step in that chain returns `nil`, or a value you're not
expecting? What if there is a deeply-nested list somewhere in the structure, or
for some reason, the structs don't match. What happens when one manager has a
single employee that is not in a list, while all of the other managers have
lists of employees?

On a project I work on, we have to grab everything from 6-7 levels
deep, in lists of maps with lists of maps, and it quickly gets complex handling
potential edge cases at each level. Something like XPath for Maps/Structs would
be great, so you could call `"//Company/Manager/Employee/PhoneNumber"` on the
arbitrary structure and get all elements that matched every part of the key.

That's what I've attempted to do with `DeepGet`. 

```elixir
phone_numbers =
  DeepGet.deep_get(company, [:managers, :employees, :phone_numbers])
```

## Examples

```elixir
iex> people = [
  %{id: 1, name: %{first: "Alice"}, age: 40},
  %{id: 2, name: %{first: "Bob"}, age: 22},
  %{id: 3, name: %{first: "Carol"}, age: 32},
  %{id: 4, name: %{first: "Dan"}, age: 47}
]

iex> DeepGet.deep_get(people, [:name, :first])
["Alice", "Bob", "Carol", "Dan"]
```

Anything that can be used as a key will make a valid path. Examples use atoms,
but strings, ints, tuples, etc... will work, as long as you can call `Map.get`
or `Keyword.get` on your structure to fetch the value with that key.

What if your structure is very complex, with different data types that may have
all the keys, or no keys at all?

```elixir
iex> list = [
  # List with multiple nested maps, maps without starting key, strings, etc...
  %{
    a: %{
      b: [ # List with multiple nested maps
        %{c: "value 1"},
        %{c: "value 2"}
      ]
    }
  },
  "string value",
  123.45,
  %{missing: :key},
  %{
    a: %{
      b: %{
        c: nil # Different structure (b is not a list), doesn't ignore nil leaf values
      }
    }
  },
  %{
    a: [
      %{
        b: nil
      },
      %{
        b: [
          %{c: "value 3"} # List with nested map
        ]
      },
      %{
        b: [c: "value 4"] # Keyword list
      }
    ]
  },
  [
    # Nested keyword lists nested in the outer list
    [a: [b: [c: "value 5"]]],
    # Duplicate key in keyword list behaves according to normal rules
    [a: [b: [c: "value 6", c: "value 7"]]],
    # Level of duplicate key in keyword list doesn't matter
    [a: [b: [c: "value 7"], b: [c: "value 8"]]]
  ]
]

iex> DeepGet.deep_get(list, [:a, :b, :c])
["value 1", "value 2", nil, "value 3", "value 4", "value 5", "value 6", "value 7"]
```

## Installation

`DeepGet` can be installed by adding `deep_get` to your list of dependencies in
`mix.exs`:

```elixir
def deps do
  [
    {:deep_get, "~> 0.1.0"}
  ]
end
```

## Documentation

Documentation can be found at [https://hexdocs.pm/deep_get](https://hexdocs.pm/deep_get).

