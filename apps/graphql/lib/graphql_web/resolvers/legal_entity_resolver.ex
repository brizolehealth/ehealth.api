defmodule GraphQLWeb.Resolvers.LegalEntityResolver do
  @moduledoc false

  import Absinthe.Resolution.Helpers, only: [on_load: 2]
  import Ecto.Query
  import GraphQLWeb.Resolvers.Helpers.Errors, only: [format_conflict_error: 1, format_not_found_error: 1]

  alias Absinthe.Relay.Connection
  alias Core.Employees.Employee
  alias Core.LegalEntities
  alias Core.LegalEntities.LegalEntity
  alias Core.LegalEntities.LegalEntityUpdater
  alias Core.PRMRepo
  alias GraphQLWeb.Loaders.PRM

  @address_search_fields ~w(area settlement)a

  def list_legal_entities(%{filter: filter, order_by: order_by} = args, _context) do
    LegalEntity
    |> prepare_where(filter)
    |> order_by(^order_by)
    |> Connection.from_query(&PRMRepo.all/1, args)
  end

  defp prepare_where(query, []), do: query

  defp prepare_where(query, [{field, value} | tail]) when field in @address_search_fields do
    condition = [Map.put(%{}, field, value)]

    query
    |> where([l], fragment("? @> ?", l.addresses, ^condition))
    |> prepare_where(tail)
  end

  defp prepare_where(query, [{field, value} | tail]) do
    query
    |> where([l], field(l, ^field) == ^value)
    |> prepare_where(tail)
  end

  def get_legal_entity_by_id(_parent, %{id: id}, _resolution) do
    {:ok, LegalEntities.get_by_id(id)}
  end

  def load_divisions(legal_entity, args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(PRM, {:divisions, args}, legal_entity)
    |> on_load(fn loader ->
      with {:ok, offset, limit} <- Connection.offset_and_limit_for_query(args, []) do
        records = Dataloader.get(loader, PRM, {:divisions, args}, legal_entity)
        opts = [has_previous_page: offset > 0, has_next_page: length(records) > limit]

        Connection.from_slice(Enum.take(records, limit), offset, opts)
      end
    end)
  end

  def load_employees(legal_entity, args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(PRM, {:employees, args}, legal_entity)
    |> on_load(fn loader ->
      with {:ok, offset, limit} <- Connection.offset_and_limit_for_query(args, []) do
        records = Dataloader.get(loader, PRM, {:employees, args}, legal_entity)
        opts = [has_previous_page: offset > 0, has_next_page: length(records) > limit]

        Connection.from_slice(Enum.take(records, limit), offset, opts)
      end
    end)
  end

  def load_owner(parent, args, %{context: %{loader: loader}}) do
    args =
      Map.merge(args, %{
        first: 1,
        order_by: [desc: :updated_at],
        filter: [employee_type: Employee.type(:owner)]
      })

    loader
    |> Dataloader.load(PRM, {:employee, args}, parent)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, PRM, {:employee, args}, parent)}
    end)
  end

  def load_related_legal_entities(legal_entity, args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(PRM, {:merged_from_legal_entities, args}, legal_entity)
    |> on_load(fn loader ->
      {:ok, :forward, limit} = Connection.limit(args)

      offset =
        case Connection.offset(args) do
          {:ok, offset} when is_integer(offset) -> offset
          _ -> 0
        end

      records = Dataloader.get(loader, PRM, {:merged_from_legal_entities, args}, legal_entity)
      opts = [has_previous_page: offset > 0, has_next_page: length(records) > limit]

      Connection.from_slice(Enum.take(records, limit), offset, opts)
    end)
  end

  def nhs_verify(%{id: id}, %{context: %{client_id: client_id}}) do
    with {:ok, legal_entity} <- LegalEntities.nhs_verify(id, client_id) do
      {:ok, %{legal_entity: legal_entity}}
    else
      # todo: remove after fallback error handling is done
      {:error, {:conflict, error}} ->
        {:error, format_conflict_error(error)}

      {:error, {:not_found, error}} ->
        {:error, format_not_found_error(error)}

      error ->
        error
    end
  end

  def deactivate(%{id: id}, %{context: context}) do
    with {:ok, legal_entity} <- LegalEntityUpdater.deactivate(id, context.headers) do
      {:ok, %{legal_entity: legal_entity}}
    else
      # todo: remove after fallback error handling is done
      {:error, {:conflict, error}} ->
        {:error, format_conflict_error(error)}

      {:error, {:not_found, error}} ->
        {:error, format_not_found_error(error)}

      error ->
        error
    end
  end
end
