defmodule Core.DeclarationRequests.API.V2.MpiSearch do
  @moduledoc """
  Provides mpi search
  """

  @mpi_api Application.get_env(:core, :api_resolvers)[:mpi]

  def search(%{"auth_phone_number" => _} = search_params) do
    search_params
    |> @mpi_api.search([])
    |> search_result(:all)
  end

  def search(person_search_params, headers \\ []) when is_list(person_search_params) do
    Enum.reduce_while(person_search_params, {:ok, nil}, fn search_params_set, acc ->
      case search_params_set
           |> @mpi_api.search(headers)
           |> search_result(:one) do
        {:ok, nil} -> {:cont, acc}
        {:ok, person} -> {:halt, {:ok, person}}
        err -> {:halt, err}
      end
    end)
  end

  defp search_result({:ok, %{"data" => data}}, :all), do: {:ok, data}
  defp search_result({:ok, %{"data" => [person | _]}}, :one), do: {:ok, person}
  defp search_result({:ok, %{"data" => _}}, :one), do: {:ok, nil}
  defp search_result({:error, %HTTPoison.Error{reason: reason}}, _), do: {:error, reason}
  defp search_result(error, _), do: error
end
