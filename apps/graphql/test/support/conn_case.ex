defmodule GraphQLWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common datastructures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate
  alias Core.Repo
  alias Core.PRMRepo
  alias Core.EventManagerRepo
  alias Ecto.Adapters.SQL.Sandbox
  alias Phoenix.ConnTest

  using do
    quote do
      # Import conveniences for testing with connections
      use Phoenix.ConnTest

      # The default endpoint for testing
      @endpoint GraphQLWeb.Endpoint

      @graphql_path "/graphql"

      @consumer_id_header "x-consumer-id"
      @consumer_metadata_header "x-consumer-metadata"
      @drfo_header "drfo"

      def put_scope(conn, scope), do: put_req_header(conn, @endpoint.scope_header(), scope)

      def put_consumer_id(conn, id \\ Ecto.UUID.generate()), do: put_req_header(conn, @consumer_id_header, id)

      def put_drfo(conn, drfo \\ "002233445566"), do: put_req_header(conn, @drfo_header, drfo)

      def put_client_id(conn, id \\ Ecto.UUID.generate()) do
        metadata = Jason.encode!(%{"client_id" => id})
        put_req_header(conn, @consumer_metadata_header, metadata)
      end

      def post_query(conn, query, variables \\ %{}) do
        post(conn, @graphql_path, %{query: query, variables: variables})
      end
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Repo)
    :ok = Sandbox.checkout(PRMRepo)
    :ok = Sandbox.checkout(EventManagerRepo)

    unless tags[:async] do
      Sandbox.mode(Repo, {:shared, self()})
      Sandbox.mode(PRMRepo, {:shared, self()})
      Sandbox.mode(EventManagerRepo, {:shared, self()})
    end

    {:ok, conn: ConnTest.build_conn()}
  end
end
