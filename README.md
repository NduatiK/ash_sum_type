# AshSumType

`AshSumType` is a Spark DSL for defining custom Ash types that behave like algebraic sum types.

It lets you declare tagged variants with optional carried fields, work with them in Elixir as atoms or tuples, and persist them through Ash as maps.

## Defining A Sum Type

```elixir
defmodule MyApp.Result do
  use AshSumType

  variant :ok do
    field :value, :integer, allow_nil?: false
  end

  variant :error do
    field :message, :string, allow_nil?: false
  end
end
```

For nullary variants, you can also use a shorthand:

```elixir
defmodule MyApp.Player do
  use AshSumType, variants: [:x, :o]
end
```

This defines an Ash type with two variants:

- `:ok`, which carries an integer
- `:error`, which carries a string message

## What It Provides

- A compact DSL for declaring variants
- Validation of fields through regular Ash types
- In-memory values represented as atoms or tuples
- Database/native values represented as maps with a reserved `__variant__` key
- Support for nesting one sum type inside another
- Use as a normal Ash attribute type

## Installation

Add the dependency to `mix.exs`:

```elixir
def deps do
  [
    {:ash_sum_type, "~> 1.0.0"}
  ]
end
```

## Constructing Values

You can construct values either from a variant name plus named fields, or from an existing atom/tuple representation.

```elixir
iex> MyApp.Result.new(:ok, value: 1)
{:ok, {:ok, 1}}

# Or directly with a tuple
iex> MyApp.Result.new({:error, "not found"})
{:ok, {:error, "not found"}}

iex> MyApp.Result.new!(:ok, value: 1)
{:ok, 1}

# Or directly with a tuple
iex> MyApp.Result.new!({:ok, 1})
{:ok, 1}
```

Nullary variants are represented as bare atoms:

```elixir
defmodule MyApp.Player do
  use AshSumType

  variant :x
  variant :o
end

iex> MyApp.Player.new(:x)
{:ok, :x}
```

## Persistence Format

In memory, values are represented as:

- `:variant` for variants with no fields
- `{:variant, field1, field2, ...}` for variants with carried fields

When dumped to Ash/native storage, they become maps:

```elixir
iex> MyApp.Result.dump_to_native({:ok, 1}, [])
{:ok, %{__variant__: :ok, value: 1}}

iex> MyApp.Player.dump_to_native(:x, [])
{:ok, %{__variant__: :x}}
```

The `__variant__` key is reserved for the variant tag.

## Using It In Ash Resources

```elixir
defmodule MyApp.GameWinner do
  use AshSumType

  variant :player do
    field :player, MyApp.Player, allow_nil?: false
  end

  variant :draw
end

defmodule MyApp.Game do
  use Ash.Resource,
    domain: MyApp.Games,
    data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :winner, MyApp.GameWinner, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:winner]
    end
  end
end

defmodule MyApp.Games do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource MyApp.Game do
      define :create_game, action: :create, args: [:winner]
    end
  end
end
```

Example usage:

```elixir
MyApp.Games.create_game!({:player, :x})
```

## Validation Behavior

Carried fields are validated with the Ash type you declare for each field. For example, this will fail because `:value` must be an integer:

```elixir
iex> MyApp.Result.new(:ok, value: "nope")
{:error, error}
```

Unknown variants, unknown carried fields, invalid field values, and wrong tuple arity are rejected.

## Nesting

A field can itself be another `AshSumType` type:

```elixir
defmodule MyApp.GameWinner do
  use AshSumType

  variant :player do
    field :player, MyApp.Player, allow_nil?: false
  end

  variant :draw
end
```

This allows values like:

```elixir
{:player, :x}
```

## API Summary

- `new/1` validates an existing atom or tuple representation
- `new/2` constructs a value from a variant name and named fields
- `new!/1` and `new!/2` are raising variants
- `variants/0` returns the declared variants
- `variant_names/0` returns declared variant names
- `fields/1` returns the fields for a variant
