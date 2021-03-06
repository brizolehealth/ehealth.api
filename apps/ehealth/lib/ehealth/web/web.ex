defmodule EHealth.Web do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller, namespace: EHealth.Web
      import Plug.Conn
      import EHealth.Proxy
      import EHealthWeb.Router.Helpers
      import Core.API.Helpers.Connection
    end
  end

  def view do
    quote do
      use Phoenix.View, root: ""
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
      import Core.API.Helpers.Connection
      import EHealth.Web.Plugs.ClientContext
      import EHealth.Web.Plugs.ContractType, only: [upcase_contract_type_param: 2]
      import EHealth.Web.Plugs.Headers
    end
  end

  def plugs do
    quote do
      import EHealth.Proxy
      import Core.API.Helpers.Connection, only: [get_header_name: 1, get_client_id: 1]
      import Plug.Conn, only: [put_status: 2, halt: 1, get_req_header: 2, assign: 3]
      import Phoenix.Controller, only: [render: 2, render: 3, put_view: 2]
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
