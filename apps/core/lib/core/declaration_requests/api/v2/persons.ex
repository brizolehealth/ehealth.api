defmodule Core.DeclarationRequests.API.V2.Persons do
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

    %{
      "type" => "BIRTH_CERTIFICATE",
      "digits" => Regex.replace(~r/[^0-9]/iu, number, ""),
      "birth_date" => person["birth_date"],
      "last_name" => person["last_name"] |> String.replace(~r{\s+}, "") |> String.downcase()
    }
  end

  def adult_document_search_params(person) do
    documents =
      person
      |> Map.get("documents", [])
      |> Enum.map(fn
        %{"type" => type, "number" => number} ->
          %{"type" => type, "number" => number |> String.downcase() |> Translit.translit(), "status" => @person_active}
      end)

    %{"documents" => documents, "status" => @person_active}
  end

  def get_search_params(person_data) do
    birth_date = person_data["birth_date"]
    tax_id = person_data["tax_id"]

    age = Timex.diff(Timex.now(), Date.from_iso8601!(birth_date), :years)

    birth_date_tax_id_params = %{
      "birth_date" => birth_date,
      "tax_id" => tax_id,
      "status" => @person_active
    }

    search_params =
      cond do
        age < 14 && tax_id && birth_date ->
          [
            birth_date_tax_id_params,
            child_document_search_params(person_data)
          ]

        age < 14 ->
          [child_document_search_params(person_data)]

        age > 14 && tax_id && birth_date ->
          [birth_date_tax_id_params]

        age > 14 ->
          [adult_document_search_params(person_data)]
      end

    {:ok, search_params}
  end
end
