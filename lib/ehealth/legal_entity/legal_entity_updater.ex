defmodule EHealth.LegalEntity.LegalEntityUpdater do
  @moduledoc false

  import EHealth.Utils.Pipeline
  import EHealth.Utils.Connection, only: [get_consumer_id: 1]

  alias EHealth.LegalEntity.API
  alias EHealth.Employee.API, as: EmployeeAPI
  alias EHealth.Employee.EmployeeUpdater
  alias EHealth.API.PRM

  require Logger

  @legal_entity_status_active "ACTIVE"

  def deactivate(id, headers) do
    pipe_data = %{id: id, headers: headers}
    with {:ok, pipe_data} <- get_legal_entity(pipe_data),
         {:ok, pipe_data} <- check_transition(pipe_data),
         {:ok, pipe_data} <- deactivate_employees(pipe_data),
         {:ok, pipe_data} <- update_legal_entity_status(pipe_data) do
         end_pipe({:ok, pipe_data})
    end
  end

  def get_legal_entity(%{id: id, headers: headers} = pipe_data) do
    id
    |> API.get_legal_entity_by_id(headers)
    |> case do
         {:ok, legal_entity, _} ->
           put_in_pipe(legal_entity, :legal_entity, pipe_data)
         err -> err
       end
  end

  def check_transition(%{legal_entity: %{"is_active" => true, "status" => @legal_entity_status_active}} =
    pipe_data),
    do: {:ok, pipe_data}

  def check_transition(_pipe_data) do
    {:error, {:conflict, "Legal entity is not ACTIVE and cannot be updated"}}
  end

  def get_active_employees(%{legal_entity: legal_entity, headers: headers} = pipe_data) do
    %{
      status: "APPROVED",
      is_active: true,
      legal_entity_id: legal_entity["id"],
    }
    |> EmployeeAPI.get_employees(headers)
    |> put_success_api_response_in_pipe(:employees_active, pipe_data)
  end

  def deactivate_employees(%{legal_entity: legal_entity, headers: headers} = pipe_data, starting_after \\ nil) do
    employees_resp = %{
      status: "APPROVED",
      is_active: true,
      legal_entity_id: legal_entity["id"],
    }
    |> set_paging_after(starting_after)
    |> EmployeeAPI.get_employees(headers)

    case employees_resp do
      {:ok, %{"paging" => %{"cursors" => cursors, "has_more" => true}}} ->
        error =
          employees_resp
          |> deactivate_employees_page(headers)
          |> check_deactivated_employees_error()
        case error do
          nil -> deactivate_employees(pipe_data, cursors["starting_after"])
          error -> {:error, error}
        end
      {:ok, %{"paging" => %{"has_more" => false}}} ->
        error =
          employees_resp
          |> deactivate_employees_page(headers)
          |> check_deactivated_employees_error()
        case error do
          nil -> {:ok, pipe_data}
          error -> {:error, error}
        end
      {:error, err} -> {:error, err}
    end
  end

  @doc """
  Find first error
  """
  def check_deactivated_employees_error(deactivated_employees) do
    deactivated_employees
    |> Enum.reduce_while(nil, fn {id, resp}, acc ->
      case resp do
        {:error, err} ->
          log_deactivate_employee_error(err, id)
          {:halt, err}
        _ -> {:cont, acc}
      end
    end)
  end

  def deactivate_employees_page({:ok, %{"data" => employees}}, headers) do
    employees
    |> Enum.map(&(Task.async(fn ->
      {&1["id"], EmployeeUpdater.deactivate(&1["id"], headers)}
    end)))
    |> Enum.map(&Task.await/1)
  end
  def deactivate_employees_page({:error, err}), do: err

  def update_legal_entity_status(%{legal_entity: legal_entity, headers: headers} = pipe_data) do
    headers
    |> get_update_legal_entity_params()
    |> put_legal_entity_status()
    |> PRM.update_legal_entity(legal_entity["id"], headers)
    |> put_success_api_response_in_pipe(:legal_entity_updated, pipe_data)
  end

  defp get_update_legal_entity_params(headers) do
    %{
      updated_by: get_consumer_id(headers),
      end_date: Date.utc_today() |> Date.to_iso8601()
    }
  end

  def put_legal_entity_status(params), do: Map.put(params, "status", "CLOSED")

  defp set_paging_after(params, nil), do: params
  defp set_paging_after(params, starting_after) do
    Map.put(params, "starting_after", starting_after)
  end

  defp log_deactivate_employee_error(error, id) do
    Logger.error("Failed to deactivate employee with id \"#{id}\". Reason: #{inspect error}")
  end
end
