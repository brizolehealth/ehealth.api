defmodule Core.DeclarationRequests.API.V1.Persons do
  @moduledoc false

  @person_active "active"
  def child_document_search_params(person) do
    number =
      person
      |> Map.get("documents", [])
      |> Enum.reduce_while("", fn
        %{"type" => "BIRTH_CERTIFICATE", "number" => number}, _ -> {:halt, number}
        _, acc -> {:cont, acc}
      end)

    [
      %{
        "birth_date" => person["birth_date"],
        "tax_id" => person["tax_id"]
      },
      %{
        "type" => "BIRTH_CERTIFICATE",
        "digits" => Regex.replace(~r/[^0-9]/iu, number, ""),
        "birth_date" => person["birth_date"],
        "last_name" => String.replace(person["last_name"], ~r{\s+}, "")
      }
    ]
  end

  def adult_document_search_params(person) do
  end

  def get_search_params(person_data) do
    birth_date = person_data["birth_date"]
    tax_id = person_data["tax_id"]

    age = Timex.diff(Timex.now(), Date.from_iso8601!(birth_date), :years)

    cond do
      age < 14 && tax_id && birth_date ->
        child_document_search_params(person_data)
    end
    |> put_search_params("status", @person_active)
  end

  defp put_search_params(map, _key, nil), do: map
  defp put_search_params(map, key, value), do: Map.put(map, key, value)
end
