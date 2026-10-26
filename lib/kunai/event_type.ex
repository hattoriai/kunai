defmodule Kunai.EventType do
  @moduledoc """
  An event the app declares in its catalog (`Kunai.Catalog`): its name,
  what it says, the scopes an endpoint needs to receive it, the shape of
  its object, the fields kept out of it, and an example for test events.
  """

  @type field_type ::
          :string
          | :integer
          | :number
          | :boolean
          | :datetime
          | :date
          | :map
          | {:array, field_type()}
          | keyword()

  @type t :: %__MODULE__{
          name: String.t(),
          doc: String.t() | nil,
          scopes: [String.t()],
          schema: keyword(field_type()) | nil,
          redact: [String.t()],
          example: map() | nil
        }

  defstruct [:name, :doc, :schema, :example, scopes: [], redact: []]

  @name ~r/\A[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+\z/

  @doc false
  # Built when the catalog compiles: a mistake is a compile error there.
  def new!(name, opts) do
    unless is_binary(name) and Regex.match?(@name, name) do
      raise ArgumentError,
            "an event's name is words of lowercase letters, digits and _ " <>
              "between dots, such as \"page.updated\", got: #{inspect(name)}"
    end

    opts =
      Keyword.validate!(opts, [:doc, :schema, :example, scopes: [], redact: []])

    if schema = opts[:schema], do: check_schema!(name, schema)

    %__MODULE__{
      name: name,
      doc: opts[:doc],
      scopes: Enum.map(opts[:scopes], &to_string/1),
      schema: opts[:schema],
      redact: Enum.map(opts[:redact], &to_string/1),
      example: opts[:example]
    }
  end

  @scalars [:string, :integer, :number, :boolean, :datetime, :date, :map]

  defp check_schema!(name, schema) do
    unless Keyword.keyword?(schema) do
      raise ArgumentError,
            "the schema of #{name} is a keyword list of fields, got: #{inspect(schema)}"
    end

    Enum.each(schema, fn {field, type} -> check_type!(name, field, type) end)
  end

  defp check_type!(_name, _field, type) when type in @scalars, do: :ok
  defp check_type!(name, field, {:array, type}), do: check_type!(name, field, type)
  defp check_type!(name, _field, [{_, _} | _] = nested), do: check_schema!(name, nested)

  defp check_type!(name, field, type) do
    raise ArgumentError,
          "the field #{field} of #{name} has an unknown type #{inspect(type)}: " <>
            "one of #{inspect(@scalars)}, {:array, type} or a keyword list"
  end

  @doc """
  The JSON Schema of the event's payload, with its object's fields when
  the event declares them.
  """
  @spec json_schema(t()) :: map()
  def json_schema(%__MODULE__{} = type) do
    object = if type.schema, do: object_schema(type.schema), else: %{"type" => "object"}

    %{
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "title" => type.name,
      "description" => type.doc,
      "type" => "object",
      "required" => ["id", "type", "created_at", "data"],
      "properties" => %{
        "id" => %{"type" => "string", "pattern" => "^evt_"},
        "object" => %{"const" => "event"},
        "type" => %{"const" => type.name},
        "created_at" => %{"type" => "string", "format" => "date-time"},
        "api_version" => %{"type" => ["string", "null"]},
        "actor" => %{"type" => ["object", "null"]},
        "data" => %{
          "type" => "object",
          "properties" => %{
            "object" => object,
            "previous" => %{"type" => ["object", "null"]}
          }
        }
      }
    }
    |> reject_nil()
  end

  defp object_schema(fields) do
    %{
      "type" => "object",
      "properties" =>
        Map.new(fields, fn {field, type} -> {to_string(field), field_schema(type)} end)
    }
  end

  defp field_schema(:string), do: %{"type" => "string"}
  defp field_schema(:integer), do: %{"type" => "integer"}
  defp field_schema(:number), do: %{"type" => "number"}
  defp field_schema(:boolean), do: %{"type" => "boolean"}
  defp field_schema(:datetime), do: %{"type" => "string", "format" => "date-time"}
  defp field_schema(:date), do: %{"type" => "string", "format" => "date"}
  defp field_schema(:map), do: %{"type" => "object"}
  defp field_schema({:array, type}), do: %{"type" => "array", "items" => field_schema(type)}
  defp field_schema(nested) when is_list(nested), do: object_schema(nested)

  defp reject_nil(map), do: map |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
end
