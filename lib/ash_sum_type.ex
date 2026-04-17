defmodule AshSumType do
  @moduledoc """
  A Spark DSL for defining Ash types that behave like algebraic sum types.

  Each module that `use`s `AshSumType` becomes an Ash type. Values are
  represented in memory as tuples whose first element is the variant tag (must be an atom):

      defmodule DrinkSize do
        use AshSumType, variants: [:small, :large]
      end

      defmodule Result do
        use AshSumType

        variant :ok do
          field :value, :integer
        end

        variant :error do
          field :message, :string, allow_nil?: true
        end
      end

      Result.new(:ok, value: 1)
      # {:ok, {:ok, 1}}
      
      Result.new({:ok, 1})
      # {:ok, {:ok, 1}}


  This library stores sum-type values in the database as maps using the reserved
  `__variant__` key, while exposing atoms/tuples in memory.

  `fields` values are not nullable by default.
  """

  defmodule Field do
    @moduledoc "Represents a field carried by a sum-type variant."

    defstruct [
      :name,
      :type,
      :constraints,
      :allow_nil?,
      :description,
      :__identifier__,
      :__spark_metadata__
    ]
  end

  defmodule Variant do
    @moduledoc "Represents one variant of a sum type."

    defstruct [
      :name,
      :__identifier__,
      :__spark_metadata__,
      fields: []
    ]
  end

  defmodule Runtime do
    @moduledoc false

    alias Ash.Type.CompositeTypeHelpers
    alias AshSumType.{Field, Variant}
    @variant_key :__variant__
    @variant_key_string "__variant__"

    def new(variants_by_name, variant_name, values \\ %{}) do
      with {:ok, variant} <- fetch_variant(variants_by_name, variant_name),
           {:ok, casted_values} <- cast_named_values(variant, values) do
        {:ok, to_variant_value(variant.name, casted_values)}
      end
    end

    def cast_input(_variants_by_name, nil), do: {:ok, nil}

    def cast_input(variants_by_name, value) when is_atom(value) do
      with {:ok, variant} <- fetch_variant(variants_by_name, value),
           {:ok, casted_values} <- cast_positional_values(variant, []) do
        {:ok, to_variant_value(variant.name, casted_values)}
      end
    end

    def cast_input(variants_by_name, value) when is_tuple(value) do
      case Tuple.to_list(value) do
        [variant_name | values] when is_atom(variant_name) ->
          with {:ok, variant} <- fetch_variant(variants_by_name, variant_name),
               :ok <- validate_tuple_representation(variant, values, value),
               {:ok, casted_values} <- cast_positional_values(variant, values) do
            {:ok, to_variant_value(variant.name, casted_values)}
          end

        _ ->
          :error
      end
    end

    def cast_input(variants_by_name, value) when is_map(value) do
      variant_name = Map.get(value, @variant_key) || Map.get(value, @variant_key_string)

      if variant_name do
        new(
          variants_by_name,
          variant_name,
          Map.drop(value, [@variant_key, @variant_key_string])
        )
      else
        :error
      end
    end

    def cast_input(_, _), do: :error

    def cast_stored(_variants_by_name, nil), do: {:ok, nil}

    def cast_stored(variants_by_name, value) when is_map(value),
      do: cast_input(variants_by_name, value)

    def cast_stored(_, _), do: :error

    def dump_to_native(_variants_by_name, nil), do: {:ok, nil}

    def dump_to_native(variants_by_name, value) do
      with {:ok, value} <- cast_input(variants_by_name, value) do
        {:ok, to_stored_map(variants_by_name, value)}
      end
    end

    def apply_constraints(variants_by_name, value), do: cast_input(variants_by_name, value)

    def matches_type?(variants_by_name, value) do
      match?({:ok, _}, cast_input(variants_by_name, value))
    end

    defp fetch_variant(variants_by_name, variant_name) when is_atom(variant_name) do
      case Map.fetch(variants_by_name, variant_name) do
        {:ok, %Variant{} = variant} ->
          {:ok, variant}

        :error ->
          {:error,
           [
             field: :variant,
             message: "unknown variant #{inspect(variant_name)}",
             value: variant_name
           ]}
      end
    end

    defp fetch_variant(_, variant_name) do
      {:error, [field: :variant, message: "variant must be an atom", value: variant_name]}
    end

    defp cast_named_values(%Variant{fields: fields}, values) do
      values = normalize_named_values(values)
      expected_fields = MapSet.new(Enum.map(fields, & &1.name))

      with :ok <- validate_no_unknown_fields(values, expected_fields),
           {:ok, casted} <-
             cast_fields(fields, fn field -> fetch_named_value(values, field.name) end) do
        {:ok, casted}
      end
    end

    defp cast_positional_values(%Variant{name: name, fields: fields}, values) do
      if length(values) == length(fields) do
        cast_fields(fields, fn field ->
          index = field_index(fields, field.name)
          {:ok, Enum.at(values, index)}
        end)
      else
        {:error,
         [
           field: name,
           message: "expected #{length(fields)} argument(s), got #{length(values)}",
           value: values
         ]}
      end
    end

    defp cast_fields(fields, fetch_value) do
      Enum.reduce_while(fields, {:ok, []}, fn %Field{} = field, {:ok, acc} ->
        case fetch_value.(field) do
          {:ok, value} ->
            case cast_field(field, value) do
              {:ok, casted_value} -> {:cont, {:ok, [casted_value | acc]}}
              {:error, error} -> {:halt, {:error, error}}
            end

          :error ->
            case cast_field(field, nil) do
              {:ok, casted_value} -> {:cont, {:ok, [casted_value | acc]}}
              {:error, error} -> {:halt, {:error, error}}
            end
        end
      end)
      |> case do
        {:ok, casted} -> {:ok, Enum.reverse(casted)}
        other -> other
      end
    end

    defp cast_field(%Field{name: name, allow_nil?: false}, nil) do
      {:error, [field: name, message: "value must not be nil", value: nil]}
    end

    defp cast_field(%Field{allow_nil?: true}, nil), do: {:ok, nil}

    defp cast_field(%Field{name: name, type: type, constraints: constraints}, value) do
      with {:ok, casted_value} <- Ash.Type.cast_input(type, value, constraints),
           {:ok, constrained_value} <- Ash.Type.apply_constraints(type, casted_value, constraints) do
        {:ok, constrained_value}
      else
        :error ->
          {:error, [field: name, message: "invalid value", value: value]}

        {:error, error} ->
          {:error,
           CompositeTypeHelpers.convert_constraint_errors_to_keyword_lists(error, name)
           |> Enum.map(&Keyword.put_new(&1, :value, value))}
      end
    end

    defp validate_tuple_representation(%Variant{fields: []}, [], value) do
      {:error,
       [field: :variant, message: "nullary variants must be provided as bare atoms", value: value]}
    end

    defp validate_tuple_representation(_variant, _values, _value), do: :ok

    defp validate_no_unknown_fields(values, expected_fields) do
      values
      |> Map.keys()
      |> Enum.reject(&(&1 in [@variant_key, @variant_key_string]))
      |> Enum.find(&(not MapSet.member?(expected_fields, normalize_field_key(&1))))
      |> case do
        nil ->
          :ok

        key ->
          {:error, [field: key, message: "unknown carried field", value: key]}
      end
    end

    defp normalize_named_values(%_{} = values),
      do: values |> Map.from_struct() |> normalize_named_values()

    defp normalize_named_values(values) when is_list(values), do: Map.new(values)
    defp normalize_named_values(values) when is_map(values), do: values

    defp normalize_field_key(key) when is_atom(key), do: key

    defp normalize_field_key(key) when is_binary(key) do
      String.to_existing_atom(key)
    rescue
      _ -> key
    end

    defp fetch_named_value(values, key) do
      case Map.fetch(values, key) do
        {:ok, value} ->
          {:ok, value}

        :error ->
          Map.fetch(values, Atom.to_string(key))
      end
    end

    defp field_index(fields, name) do
      fields
      |> Enum.map(& &1.name)
      |> Enum.find_index(&(&1 == name))
    end

    defp to_stored_map(_variants_by_name, value) when is_atom(value) do
      %{__variant__: value}
    end

    defp to_stored_map(variants_by_name, value) when is_tuple(value) do
      [variant_name | carried_values] = Tuple.to_list(value)
      {:ok, variant} = fetch_variant(variants_by_name, variant_name)

      variant.fields
      |> Enum.zip(carried_values)
      |> Enum.reduce(%{__variant__: variant_name}, fn {field, field_value}, acc ->
        Map.put(acc, field.name, dump_field_to_native(field, field_value))
      end)
    end

    defp dump_field_to_native(%Field{type: type, constraints: constraints}, value) do
      case Ash.Type.dump_to_native(type, value, constraints) do
        {:ok, dumped} -> dumped
        _ -> value
      end
    end

    defp to_variant_tuple(variant_name, values) do
      List.to_tuple([variant_name | values])
    end

    defp to_variant_value(variant_name, []), do: variant_name
    defp to_variant_value(variant_name, values), do: to_variant_tuple(variant_name, values)
  end

  defmodule Dsl do
    @moduledoc false

    @field %Spark.Dsl.Entity{
      name: :field,
      target: Field,
      describe: "A carried field for a variant.",
      args: [:name, :type],
      identifier: :name,
      schema: [
        name: [
          type: :atom,
          required: true,
          doc: "The field name."
        ],
        type: [
          type: Ash.OptionsHelpers.ash_type(),
          required: true,
          doc: "The Ash type of the field."
        ],
        constraints: [
          type: :keyword_list,
          default: [],
          doc: "Type constraints for the field."
        ],
        allow_nil?: [
          type: :boolean,
          default: false,
          doc: "Whether the field can be nil. Defaults to false."
        ],
        description: [
          type: :string,
          doc: "Documentation for the field."
        ]
      ]
    }

    @variant %Spark.Dsl.Entity{
      name: :variant,
      target: Variant,
      describe: "Declare a sum-type variant.",
      args: [:name],
      identifier: :name,
      schema: [
        name: [
          type: :atom,
          required: true,
          doc: "The variant name."
        ]
      ],
      entities: [
        fields: [@field]
      ]
    }

    @sum_type %Spark.Dsl.Section{
      name: :sum_type,
      top_level?: true,
      describe: "Declare the variants for this sum type.",
      entities: [@variant]
    }

    def normalize_variants!(variants) do
      Enum.map(variants, fn variant ->
        %{variant | fields: Enum.map(variant.fields || [], &normalize_field!/1)}
      end)
    end

    defp normalize_field!(field) do
      type = Ash.Type.get_type!(field.type)

      case Ash.Type.init(type, field.constraints || []) do
        {:ok, constraints} ->
          %{field | type: type, constraints: constraints}

        {:error, error} ->
          raise "Invalid constraints for #{inspect(field.name)}: #{inspect(error)}"
      end
    end

    use Spark.Dsl.Extension, sections: [@sum_type]
  end

  @doc false
  def __define_sum_type__(variants) do
    quote bind_quoted: [variants: Macro.escape(variants)] do
      @variants variants
      @variants_by_name Map.new(@variants, &{&1.name, &1})

      use Ash.Type

      @doc "Returns the defined variants."
      def variants, do: @variants

      @doc "Returns the defined variant names."
      def variant_names, do: Enum.map(@variants, & &1.name)

      @doc "Returns the fields for a variant name."
      def fields(variant_name) do
        case Map.fetch(@variants_by_name, variant_name) do
          {:ok, variant} -> variant.fields
          :error -> []
        end
      end

      @doc "Validate and construct a sum-type value from an existing atom or tuple."
      def new(value) do
        case AshSumType.Runtime.cast_input(@variants_by_name, value) do
          {:ok, value} ->
            {:ok, value}

          {:error, error} ->
            Ash.Type.CompositeTypeHelpers.convert_errors_to_invalid_attributes(error)

          :error ->
            {:error, Ash.Error.to_ash_error("invalid value")}
        end
      end

      @doc "Construct a variant value from named carried fields."
      def new(variant_name, values) do
        case AshSumType.Runtime.new(@variants_by_name, variant_name, values) do
          {:ok, value} ->
            {:ok, value}

          {:error, error} ->
            Ash.Type.CompositeTypeHelpers.convert_errors_to_invalid_attributes(error)
        end
      end

      @doc "Construct a validated sum-type value or raise on invalid input."
      def new!(value) do
        value
        |> new()
        |> Ash.Helpers.unwrap_or_raise!()
      end

      @doc "Construct a variant value or raise on invalid input."
      def new!(variant_name, values) do
        variant_name
        |> new(values)
        |> Ash.Helpers.unwrap_or_raise!()
      end

      @impl true
      def storage_type(_constraints), do: :map

      @impl true
      def can_load?(_constraints), do: false

      @impl true
      def equal?(left, right), do: left == right

      @impl true
      def simple_equality?, do: true

      @impl true
      def custom_apply_constraints_array?, do: false

      @impl true
      def handle_change(_old_value, new_value, constraints),
        do: cast_input(new_value, constraints)

      @impl true
      def handle_change_array?, do: false

      @impl true
      def prepare_change(_old_value, new_value, constraints),
        do: cast_input(new_value, constraints)

      @impl true
      def prepare_change_array?, do: false

      @impl true
      def cast_input("", _constraints), do: {:ok, nil}

      @impl true
      def cast_input(value, _constraints),
        do: AshSumType.Runtime.cast_input(@variants_by_name, value)

      @impl true
      def cast_stored(value, _constraints),
        do: AshSumType.Runtime.cast_stored(@variants_by_name, value)

      @impl true
      def dump_to_native(value, _constraints),
        do: AshSumType.Runtime.dump_to_native(@variants_by_name, value)

      @impl true
      def apply_constraints(value, _constraints),
        do: AshSumType.Runtime.apply_constraints(@variants_by_name, value)

      @impl true
      def matches_type?(value, _constraints),
        do: AshSumType.Runtime.matches_type?(@variants_by_name, value)
    end
  end

  @doc false
  def handle_opts(_opts) do
    quote do
    end
  end

  @doc false
  def handle_before_compile(opts) do
    shorthand_variants =
      opts
      |> Keyword.get(:variants, [])
      |> Enum.map(&%Variant{name: &1, fields: []})

    quote bind_quoted: [shorthand_variants: Macro.escape(shorthand_variants)] do
      variants =
        (shorthand_variants ++ Spark.Dsl.Extension.get_entities(__MODULE__, [:sum_type]))
        |> AshSumType.Dsl.normalize_variants!()

      Code.eval_quoted(AshSumType.__define_sum_type__(variants), [], __ENV__)
    end
  end

  use Spark.Dsl,
    default_extensions: [extensions: [Dsl]],
    opt_schema: [
      variants: [
        type: {:list, :atom},
        default: [],
        doc: "Shorthand nullary variants to define when using `AshSumType`."
      ]
    ]
end
