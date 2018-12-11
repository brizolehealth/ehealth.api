defmodule Core.Utils.Helpers do
  @moduledoc """
  Plug.Conn helpers
  """

  def get_assoc_by_func(assoc_id, fun) do
    case fun.() do
      nil -> {:assoc_error, assoc_id}
      {:error, _} -> {:assoc_error, assoc_id}
      assoc -> {:ok, assoc}
    end
  end

  def from_filed_to_name(id_string) do
    id_string
    |> String.replace("_id", "")
    |> String.capitalize()
  end

  def convert_cap_letters_lat_to_cyr(input_string) do
    letter_mapping = %{
      "A" => "А",
      "B" => "В",
      "C" => "С",
      "E" => "Е",
      "H" => "Н",
      "I" => "І",
      "K" => "К",
      "M" => "М",
      "O" => "О",
      "P" => "Р",
      "T" => "Т",
      "X" => "Х"
    }

    input_string
    |> String.graphemes()
    |> Enum.reduce(fn c, acc ->
      if letter_mapping[c] == nil do
        acc <> c
      else
        acc <> letter_mapping[c]
      end
    end)
  end
end
