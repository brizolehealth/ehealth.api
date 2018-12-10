defmodule GraphQLWeb.Schema.CapitationContractTypes do
  @moduledoc false

  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Resolution.Helpers, only: [dataloader: 1]
  import GraphQLWeb.Resolvers.Helpers.Load, only: [load_by_args: 2, load_by_parent: 2]

  alias Absinthe.Relay.Node.ParseIDs
  alias Core.ContractRequests.CapitationContractRequest
  alias Core.Contracts.CapitationContract
  alias GraphQLWeb.Loaders.IL
  alias GraphQLWeb.Loaders.PRM
  alias GraphQLWeb.Middleware.Filtering
  alias GraphQLWeb.Resolvers.CapitationContractResolver
  alias GraphQLWeb.Resolvers.ContractResolver

  object :capitation_contract_queries do
    connection field(:capitation_contracts, node_type: :capitation_contract) do
      meta(:scope, ~w(contract:read))
      meta(:client_metadata, ~w(client_id client_type)a)
      meta(:allowed_clients, ~w(NHS MSP))

      arg(:filter, :capitation_contract_filter)
      arg(:order_by, :capitation_contract_order_by, default_value: :inserted_at_desc)

      middleware(Filtering,
        database_id: :equal,
        contract_number: :equal,
        status: :equal,
        start_date: :in,
        end_date: :in,
        is_suspended: :equal,
        legal_entity_relation: :equal,
        contractor_legal_entity: [
          database_id: :equal,
          edrpou: :equal,
          nhs_verified: :equal,
          nhs_reviewed: :equal
        ]
      )

      resolve(&CapitationContractResolver.list_contracts/2)
    end

    field :capitation_contract, :capitation_contract do
      meta(:scope, ~w(contract:read))
      meta(:client_metadata, ~w(client_id client_type)a)
      meta(:allowed_clients, ~w(NHS MSP))

      arg(:id, non_null(:id))

      middleware(ParseIDs, id: :capitation_contract)

      resolve(
        load_by_args(PRM, fn _args, %{context: context} ->
          {CapitationContract, Map.take(context, ~w(client_id client_type)a)}
        end)
      )
    end
  end

  input_object :capitation_contract_filter do
    field(:database_id, :id)
    field(:contractor_legal_entity, :legal_entity_filter)
    field(:contract_number, :string)
    field(:status, :contract_status)
    field(:start_date, :date_interval)
    field(:end_date, :date_interval)
    field(:legal_entity_relation, :legal_entity_relation)
    field(:is_suspended, :boolean)
  end

  enum :capitation_contract_order_by do
    value(:contractor_legal_entity_edrpou_asc)
    value(:contractor_legal_entity_edrpou_desc)
    value(:end_date_asc)
    value(:end_date_desc)
    value(:inserted_at_asc)
    value(:inserted_at_desc)
    value(:is_suspended_asc)
    value(:is_suspended_desc)
    value(:start_date_asc)
    value(:start_date_desc)
    value(:status_asc)
    value(:status_desc)
  end

  connection node_type: :capitation_contract do
    field :nodes, list_of(:capitation_contract) do
      resolve(fn _, %{source: conn} -> {:ok, Enum.map(conn.edges, & &1.node)} end)
    end

    edge(do: nil)
  end

  node object(:capitation_contract) do
    interface(:contract)

    field(:database_id, non_null(:id))
    field(:contract_number, :string)
    field(:parent_contract_id, :id)
    field(:parent_contract, :contract, resolve: dataloader(PRM))
    field(:contract_request_id, non_null(:id))
    field(:contract_request, non_null(:contract_request), resolve: load_by_parent(IL, CapitationContractRequest))
    field(:id_form, non_null(:string))
    field(:status, non_null(:contract_status))
    field(:status_reason, :string)
    field(:issue_city, :string)
    field(:printout_content, :string, resolve: &ContractResolver.get_printout_content/3)
    field(:start_date, non_null(:date))
    field(:end_date, non_null(:date))
    field(:is_suspended, non_null(:boolean))
    field(:contractor_legal_entity, non_null(:legal_entity), resolve: dataloader(PRM))
    field(:contractor_owner, non_null(:employee), resolve: dataloader(PRM))
    field(:contractor_base, non_null(:string))
    field(:contractor_payment_details, non_null(:contractor_payment_details))

    connection field(:contractor_divisions, node_type: :division) do
      arg(:filter, :division_filter)
      arg(:order_by, :division_order_by, default_value: :inserted_at_asc)

      # TODO: Replace it with `GraphQLWeb.Middleware.Filtering`
      middleware(GraphQLWeb.Middleware.FilterArgument)
      resolve(&CapitationContractResolver.load_contract_divisions/3)
    end

    field(:nhs_signer, :employee, resolve: dataloader(PRM))
    field(:nhs_legal_entity, :legal_entity, resolve: dataloader(PRM))
    field(:nhs_signer_base, :string)
    field(:nhs_payment_method, :nhs_payment_method)

    field(:attached_documents, non_null(list_of(:contract_document)),
      resolve: &CapitationContractResolver.get_attached_documents/3
    )

    # TODO: Timestamp fields should return :datetime type
    field(:inserted_at, non_null(:naive_datetime))
    field(:updated_at, non_null(:naive_datetime))

    connection field(:contractor_employee_divisions, node_type: :contract_employee_division) do
      arg(:filter, :contractor_employee_division_filter)
      arg(:order_by, :contractor_employee_division_order_by, default_value: :inserted_at_asc)

      # TODO: Replace it with `GraphQLWeb.Middleware.Filtering`
      middleware(GraphQLWeb.Middleware.FilterArgument)
      resolve(&CapitationContractResolver.load_contract_employees/3)
    end

    field(:external_contractor_flag, non_null(:boolean))
    field(:external_contractors, list_of(:external_contractor))
    field(:nhs_contract_price, :float)
    field(:contractor_rmsp_amount, non_null(:integer))
  end

  input_object :contractor_employee_division_filter do
    field(:division, :division_filter)
  end

  enum :contractor_employee_division_order_by do
    value(:declaration_limit_asc)
    value(:declaration_limit_desc)
    value(:inserted_at_asc)
    value(:inserted_at_desc)
    value(:staff_units_asc)
    value(:staff_units_desc)
  end

  connection node_type: :contract_employee_division do
    field :nodes, list_of(:contract_employee_division) do
      resolve(fn
        _, %{source: conn} -> {:ok, Enum.map(conn.edges, & &1.node)}
      end)
    end

    edge(do: nil)
  end

  node object(:contract_employee_division) do
    field(:database_id, non_null(:id))
    field(:staff_units, non_null(:float))
    field(:declaration_limit, non_null(:integer))
    field(:employee, non_null(:employee), resolve: dataloader(PRM))
    field(:division, non_null(:division), resolve: dataloader(PRM))
  end
end
