defmodule EHealth.Web.Cabinet.DeclarationRequestControllerTest do
  @moduledoc false

  use EHealth.Web.ConnCase
  import Mox

  alias Ecto.UUID
  alias EHealth.MockServer
  alias EHealth.Repo
  alias EHealth.DeclarationRequests.DeclarationRequest

  @person_non_create_params ~w(
    version
    national_id
    death_date
    invalid_tax_id
    is_active
    status
    inserted_by
    updated_by
    merged_ids
    id
  )

  setup :verify_on_exit!

  defmodule MithrilServer do
    @moduledoc false

    use MicroservicesHelper
    alias EHealth.MockServer

    Plug.Router.get "/admin/roles" do
      response =
        [
          %{
            id: "e945360c-8c4a-4f37-a259-320d2533cfc4",
            role_name: "DOCTOR"
          }
        ]
        |> MockServer.wrap_response()
        |> Jason.encode!()

      Plug.Conn.send_resp(conn, 200, response)
    end

    Plug.Router.get "/admin/users/8069cb5c-3156-410b-9039-a1b2f2a4136c" do
      user = %{
        "id" => "8069cb5c-3156-410b-9039-a1b2f2a4136c",
        "settings" => %{},
        "email" => "test@example.com",
        "type" => "user",
        "person_id" => "c8912855-21c3-4771-ba18-bcd8e524f14c",
        "tax_id" => "2222222225",
        "is_blocked" => false
      }

      response =
        user
        |> MockServer.wrap_response()
        |> Jason.encode!()

      Plug.Conn.send_resp(conn, 200, response)
    end

    Plug.Router.get "/admin/users/4d593e84-34dc-48d3-9e33-0628a8446956" do
      response =
        %{
          "id" => "4d593e84-34dc-48d3-9e33-0628a8446956",
          "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
          "block_reason" => nil,
          "email" => "email@example.com",
          "is_blocked" => false,
          "settings" => %{},
          "tax_id" => "12341234"
        }
        |> MockServer.wrap_response()
        |> Jason.encode!()

      Plug.Conn.send_resp(conn, 200, response)
    end

    Plug.Router.get "/admin/clients/c3cc1def-48b6-4451-be9d-3b777ef06ff9/details" do
      response =
        %{"client_type_name" => "CABINET"}
        |> MockServer.wrap_response()
        |> Jason.encode!()

      Plug.Conn.send_resp(conn, 200, response)
    end

    Plug.Router.get "/admin/clients/75dfd749-c162-48ce-8a92-428c106d5dc3/details" do
      response =
        %{"client_type_name" => "MSP"}
        |> MockServer.wrap_response()
        |> Jason.encode!()

      Plug.Conn.send_resp(conn, 200, response)
    end

    Plug.Router.get "/admin/clients/4d593e84-34dc-48d3-9e33-0628a8446956/details" do
      response =
        %{"client_type_name" => "CABINET"}
        |> MockServer.wrap_response()
        |> Jason.encode!()

      Plug.Conn.send_resp(conn, 200, response)
    end

    Plug.Router.get "/admin/users/668d1541-e4cf-4a95-a25a-60d83864ceaf" do
      user = %{
        "id" => "668d1541-e4cf-4a95-a25a-60d83864ceaf",
        "settings" => %{},
        "email" => "test@example.com",
        "type" => "user"
      }

      response =
        user
        |> MockServer.wrap_response()
        |> Jason.encode!()

      Plug.Conn.send_resp(conn, 200, response)
    end

    Plug.Router.get "/admin/users/8069cb5c-3156-410b-9039-a1b2f2a4136c/roles" do
      response =
        [
          %{
            id: UUID.generate(),
            user_id: "8069cb5c-3156-410b-9039-a1b2f2a4136c",
            role_id: "e945360c-8c4a-4f37-a259-320d2533cfc4",
            role_name: "DOCTOR"
          }
        ]
        |> MockServer.wrap_response()
        |> Jason.encode!()

      Plug.Conn.send_resp(conn, 200, response)
    end

    Plug.Router.get "/admin/users/:id" do
      Plug.Conn.send_resp(conn, 404, "")
    end
  end

  setup do
    insert(:prm, :global_parameter, %{parameter: "adult_age", value: "18"})
    insert(:prm, :global_parameter, %{parameter: "declaration_term", value: "40"})
    insert(:prm, :global_parameter, %{parameter: "declaration_term_unit", value: "YEARS"})

    register_mircoservices_for_tests([
      {MithrilServer, "OAUTH_ENDPOINT"}
    ])

    :ok
  end

  describe "create declaration request online" do
    test "success create declaration request online  for underage person for PEDIATRICIAN", %{conn: conn} do
      birth_date =
        Date.utc_today()
        |> Date.add(-365 * 10)
        |> to_string()

      expect(MPIMock, :person, fn _, _ ->
        get_person("c8912855-21c3-4771-ba18-bcd8e524f14c", 200, %{
          birth_date: birth_date,
          documents: [
            %{"type" => "BIRTH_CERTIFICATE", "number" => "1234567890"}
          ],
          tax_id: "2222222225",
          authentication_methods: [%{"type" => "NA"}],
          addresses: get_person_addresses()
        })
      end)

      role_id = UUID.generate()
      expect(MithrilMock, :get_user_by_id, fn _, _ -> {:ok, %{"data" => %{"email" => "user@email.com"}}} end)

      expect(MithrilMock, :get_roles_by_name, fn "DOCTOR", _headers ->
        {:ok, %{"data" => [%{"id" => role_id}]}}
      end)

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok,
         %{
           "data" => [
             %{
               "role_id" => role_id,
               "user_id" => UUID.generate()
             }
           ]
         }}
      end)

      expect(OPSMock, :get_latest_block, fn _params ->
        {:ok, %{"data" => %{"hash" => "some_current_hash"}}}
      end)

      legal_entity = insert(:prm, :legal_entity, id: "c3cc1def-48b6-4451-be9d-3b777ef06ff9")
      person_id = "c8912855-21c3-4771-ba18-bcd8e524f14c"
      division = insert(:prm, :division, legal_entity: legal_entity)
      employee_speciality = Map.put(speciality(), "speciality", "PEDIATRICIAN")
      additional_info = Map.put(doctor(), "specialities", [employee_speciality])

      employee =
        insert(
          :prm,
          :employee,
          division: division,
          legal_entity_id: legal_entity.id,
          additional_info: additional_info,
          speciality: employee_speciality
        )

      insert(:prm, :party_user, user_id: "8069cb5c-3156-410b-9039-a1b2f2a4136c", party: employee.party)

      expect(ManMock, :render_template, fn _id, _data ->
        {:ok, "<html><body>Printout form for declaration request.</body></html>"}
      end)

      conn =
        conn
        |> put_req_header("edrpou", "2222222220")
        |> put_req_header("x-consumer-id", "8069cb5c-3156-410b-9039-a1b2f2a4136c")
        |> put_req_header("x-consumer-metadata", Jason.encode!(%{client_id: legal_entity.id}))
        |> post(cabinet_declaration_requests_path(conn, :create), %{
          person_id: person_id,
          employee_id: employee.id,
          division_id: employee.division.id
        })

      resp = json_response(conn, 200)

      assert Kernel.trunc(Date.diff(Date.from_iso8601!(resp["data"]["end_date"]), Date.from_iso8601!(birth_date)) / 365) ==
               EHealth.GlobalParameters.get_values()["adult_age"]
               |> String.to_integer()

      assert %{
               "data" => %{
                 "seed" => "some_current_hash",
                 "employee" => %{
                   "speciality" => "PEDIATRICIAN"
                 }
               }
             } = resp

      for key <- Map.keys(resp["data"]["person"]) do
        refute key in @person_non_create_params
      end

      declaration_request = Repo.get(DeclarationRequest, get_in(resp, ~w(data id)))
      assert declaration_request.mpi_id == person_id
    end

    test "success create declaration request online  for underage person for FAMILY_DOCTOR", %{conn: conn} do
      birth_date =
        Date.utc_today()
        |> Date.add(-365 * 10)
        |> to_string()

      expect(MPIMock, :person, fn _, _ ->
        get_person("c8912855-21c3-4771-ba18-bcd8e524f14c", 200, %{
          birth_date: birth_date,
          documents: [
            %{"type" => "BIRTH_CERTIFICATE", "number" => "1234567890"}
          ],
          tax_id: "2222222225",
          authentication_methods: [%{"type" => "NA"}],
          addresses: get_person_addresses()
        })
      end)

      role_id = UUID.generate()
      expect(MithrilMock, :get_user_by_id, fn _, _ -> {:ok, %{"data" => %{"email" => "user@email.com"}}} end)

      expect(MithrilMock, :get_roles_by_name, fn "DOCTOR", _headers ->
        {:ok, %{"data" => [%{"id" => role_id}]}}
      end)

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok,
         %{
           "data" => [
             %{
               "role_id" => role_id,
               "user_id" => UUID.generate()
             }
           ]
         }}
      end)

      expect(OPSMock, :get_latest_block, fn _params ->
        {:ok, %{"data" => %{"hash" => "some_current_hash"}}}
      end)

      legal_entity = insert(:prm, :legal_entity, id: "c3cc1def-48b6-4451-be9d-3b777ef06ff9")
      person_id = "c8912855-21c3-4771-ba18-bcd8e524f14c"
      division = insert(:prm, :division, legal_entity: legal_entity)
      employee_speciality = Map.put(speciality(), "speciality", "FAMILY_DOCTOR")
      additional_info = Map.put(doctor(), "specialities", [employee_speciality])

      employee =
        insert(
          :prm,
          :employee,
          division: division,
          legal_entity_id: legal_entity.id,
          additional_info: additional_info,
          speciality: employee_speciality
        )

      insert(:prm, :party_user, user_id: "8069cb5c-3156-410b-9039-a1b2f2a4136c", party: employee.party)

      expect(ManMock, :render_template, fn _id, _data ->
        {:ok, "<html><body>Printout form for declaration request.</body></html>"}
      end)

      conn =
        conn
        |> put_req_header("edrpou", "2222222220")
        |> put_req_header("x-consumer-id", "8069cb5c-3156-410b-9039-a1b2f2a4136c")
        |> put_req_header("x-consumer-metadata", Jason.encode!(%{client_id: legal_entity.id}))
        |> post(cabinet_declaration_requests_path(conn, :create), %{
          person_id: person_id,
          employee_id: employee.id,
          division_id: employee.division.id
        })

      resp = json_response(conn, 200)

      assert Kernel.trunc(Date.diff(Date.from_iso8601!(resp["data"]["end_date"]), Date.utc_today()) / 365) ==
               EHealth.GlobalParameters.get_values()["declaration_term"]
               |> String.to_integer()

      assert %{
               "data" => %{
                 "seed" => "some_current_hash",
                 "employee" => %{
                   "speciality" => "FAMILY_DOCTOR"
                 }
               }
             } = resp

      for key <- Map.keys(resp["data"]["person"]) do
        refute key in @person_non_create_params
      end

      declaration_request = Repo.get(DeclarationRequest, get_in(resp, ~w(data id)))
      assert declaration_request.mpi_id == person_id
    end

    test "success create declaration request online  for adult person for THERAPIST", %{conn: conn} do
      birth_date =
        Date.utc_today()
        |> Date.add(-365 * 30)
        |> to_string()

      expect(MPIMock, :person, fn _, _ ->
        get_person("c8912855-21c3-4771-ba18-bcd8e524f14c", 200, %{
          birth_date: birth_date,
          documents: [
            %{"type" => "BIRTH_CERTIFICATE", "number" => "1234567890"}
          ],
          tax_id: "2222222225",
          authentication_methods: [%{"type" => "NA"}],
          addresses: get_person_addresses()
        })
      end)

      role_id = UUID.generate()
      expect(MithrilMock, :get_user_by_id, fn _, _ -> {:ok, %{"data" => %{"email" => "user@email.com"}}} end)

      expect(MithrilMock, :get_roles_by_name, fn "DOCTOR", _headers ->
        {:ok, %{"data" => [%{"id" => role_id}]}}
      end)

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok,
         %{
           "data" => [
             %{
               "role_id" => role_id,
               "user_id" => UUID.generate()
             }
           ]
         }}
      end)

      expect(OPSMock, :get_latest_block, fn _params ->
        {:ok, %{"data" => %{"hash" => "some_current_hash"}}}
      end)

      legal_entity = insert(:prm, :legal_entity, id: "c3cc1def-48b6-4451-be9d-3b777ef06ff9")
      person_id = "c8912855-21c3-4771-ba18-bcd8e524f14c"
      division = insert(:prm, :division, legal_entity: legal_entity)
      employee_speciality = Map.put(speciality(), "speciality", "THERAPIST")
      additional_info = Map.put(doctor(), "specialities", [employee_speciality])

      employee =
        insert(
          :prm,
          :employee,
          division: division,
          legal_entity_id: legal_entity.id,
          additional_info: additional_info,
          speciality: employee_speciality
        )

      insert(:prm, :party_user, user_id: "8069cb5c-3156-410b-9039-a1b2f2a4136c", party: employee.party)

      expect(ManMock, :render_template, fn _id, _data ->
        {:ok, "<html><body>Printout form for declaration request.</body></html>"}
      end)

      conn =
        conn
        |> put_req_header("edrpou", "2222222220")
        |> put_req_header("x-consumer-id", "8069cb5c-3156-410b-9039-a1b2f2a4136c")
        |> put_req_header("x-consumer-metadata", Jason.encode!(%{client_id: legal_entity.id}))
        |> post(cabinet_declaration_requests_path(conn, :create), %{
          person_id: person_id,
          employee_id: employee.id,
          division_id: employee.division.id
        })

      resp = json_response(conn, 200)

      assert Kernel.trunc(Date.diff(Date.from_iso8601!(resp["data"]["end_date"]), Date.utc_today()) / 365) ==
               EHealth.GlobalParameters.get_values()["declaration_term"]
               |> String.to_integer()

      assert %{
               "data" => %{
                 "seed" => "some_current_hash",
                 "employee" => %{
                   "speciality" => "THERAPIST"
                 }
               }
             } = resp

      for key <- Map.keys(resp["data"]["person"]) do
        refute key in @person_non_create_params
      end

      declaration_request = Repo.get(DeclarationRequest, get_in(resp, ~w(data id)))
      assert declaration_request.mpi_id == person_id
    end
  end

  @user_id "4d593e84-34dc-48d3-9e33-0628a8446956"
  @person_id "0c65d15b-32b4-4e82-b53d-0572416d890e"

  describe "declaration requests list via cabinet" do
    test "declaration requests list is successfully showed", %{conn: conn} do
      expect(MithrilMock, :get_user_by_id, fn user_id, _headers ->
        {:ok,
         %{
           "data" => %{
             "id" => user_id,
             "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
             "tax_id" => "12341234",
             "is_blocked" => false
           }
         }}
      end)

      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{"tax_id" => "12341234"})
      end)

      declaration_request_in = insert(:il, :declaration_request, mpi_id: @person_id, data: fixture_params())
      declaration_request_out = insert(:il, :declaration_request, data: fixture_params())

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> get(cabinet_declaration_requests_path(conn, :index))

      resp = json_response(conn, 200)

      declaration_request_ids = Enum.map(resp["data"], fn item -> Map.get(item, "id") end)
      assert declaration_request_in.id in declaration_request_ids
      refute declaration_request_out.id in declaration_request_ids

      schema =
        "specs/json_schemas/cabinet/declaration_requests_list.json"
        |> File.read!()
        |> Jason.decode!()

      assert :ok = NExJsonSchema.Validator.validate(schema, resp)
    end

    test "declaration requests list with search params", %{conn: conn} do
      expect(MithrilMock, :get_user_by_id, fn user_id, _headers ->
        {:ok,
         %{
           "data" => %{
             "id" => user_id,
             "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
             "tax_id" => "12341234",
             "is_blocked" => false
           }
         }}
      end)

      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{"tax_id" => "12341234"})
      end)

      search_status = DeclarationRequest.status(:approved)
      search_start_year = "2018"

      declaration_request_in =
        insert(
          :il,
          :declaration_request,
          mpi_id: @person_id,
          status: search_status,
          data: fixture_params(%{"start_date" => "2018-03-02"})
        )

      declaration_request_out = insert(:il, :declaration_request, mpi_id: @person_id, data: fixture_params())

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> get(cabinet_declaration_requests_path(conn, :index), %{status: search_status, start_year: search_start_year})

      resp = json_response(conn, 200)

      declaration_request_ids = Enum.map(resp["data"], fn item -> Map.get(item, "id") end)
      assert declaration_request_in.id in declaration_request_ids
      refute declaration_request_out.id in declaration_request_ids

      schema =
        "specs/json_schemas/cabinet/declaration_requests_list.json"
        |> File.read!()
        |> Jason.decode!()

      assert :ok = NExJsonSchema.Validator.validate(schema, resp)
    end

    test "declaration requests list ignore invalid search params", %{conn: conn} do
      expect(MithrilMock, :get_user_by_id, fn user_id, _headers ->
        {:ok,
         %{
           "data" => %{
             "id" => user_id,
             "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
             "tax_id" => "12341234",
             "is_blocked" => false
           }
         }}
      end)

      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{"tax_id" => "12341234"})
      end)

      for _ <- 1..2, do: insert(:il, :declaration_request, mpi_id: @person_id, data: fixture_params())

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> get(cabinet_declaration_requests_path(conn, :index), %{test: UUID.generate()})

      resp = json_response(conn, 200)
      assert length(resp["data"]) == 2

      schema =
        "specs/json_schemas/cabinet/declaration_requests_list.json"
        |> File.read!()
        |> Jason.decode!()

      assert :ok = NExJsonSchema.Validator.validate(schema, resp)
    end

    test "failed when person is not valid", %{conn: conn} do
      expect(MithrilMock, :get_user_by_id, fn user_id, _headers ->
        {:ok,
         %{
           "data" => %{
             "id" => user_id,
             "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
             "tax_id" => "12341234",
             "is_blocked" => false
           }
         }}
      end)

      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{"tax_id" => "11111111"})
      end)

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> get(cabinet_declaration_requests_path(conn, :index))

      assert resp = json_response(conn, 401)
      assert %{"type" => "access_denied", "message" => "Person not found"} == resp["error"]
    end

    test "failed when user is blocked", %{conn: conn} do
      expect(MithrilMock, :get_user_by_id, fn user_id, _headers ->
        {:ok,
         %{
           "data" => %{
             "id" => user_id,
             "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
             "tax_id" => "12341234",
             "is_blocked" => true
           }
         }}
      end)

      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{"tax_id" => "12341234"})
      end)

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> get(cabinet_declaration_requests_path(conn, :index))

      assert resp = json_response(conn, 401)
      assert %{"type" => "access_denied"} == resp["error"]
    end

    test "declaration requests list - expired status is not shown", %{conn: conn} do
      expect(MithrilMock, :get_user_by_id, fn user_id, _headers ->
        {:ok,
         %{
           "data" => %{
             "id" => user_id,
             "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
             "tax_id" => "12341234",
             "is_blocked" => false
           }
         }}
      end)

      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{"tax_id" => "12341234"})
      end)

      declaration_request_in = insert(:il, :declaration_request, mpi_id: @person_id, data: fixture_params())

      declaration_request_out =
        insert(
          :il,
          :declaration_request,
          mpi_id: @person_id,
          status: DeclarationRequest.status(:expired),
          data: fixture_params()
        )

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> get(cabinet_declaration_requests_path(conn, :index))

      resp = json_response(conn, 200)

      declaration_request_ids = Enum.map(resp["data"], fn item -> Map.get(item, "id") end)
      assert declaration_request_in.id in declaration_request_ids
      refute declaration_request_out.id in declaration_request_ids

      schema =
        "specs/json_schemas/cabinet/declaration_requests_list.json"
        |> File.read!()
        |> Jason.decode!()

      assert :ok = NExJsonSchema.Validator.validate(schema, resp)
    end

    test "declaration requests list with status search param - expired status means empty list", %{conn: conn} do
      expect(MithrilMock, :get_user_by_id, fn user_id, _headers ->
        {:ok,
         %{
           "data" => %{
             "id" => user_id,
             "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
             "tax_id" => "12341234",
             "is_blocked" => false
           }
         }}
      end)

      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{"tax_id" => "12341234"})
      end)

      search_status = DeclarationRequest.status(:expired)
      search_start_year = "2018"

      insert(
        :il,
        :declaration_request,
        mpi_id: @person_id,
        status: search_status,
        data: fixture_params(%{"start_date" => "2018-03-02"})
      )

      insert(:il, :declaration_request, mpi_id: @person_id, data: fixture_params())

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> get(cabinet_declaration_requests_path(conn, :index), %{status: search_status, start_year: search_start_year})

      resp = json_response(conn, 200)
      assert resp["data"] == []
    end
  end

  describe "declaration request details via cabinet" do
    test "declaration request details is successfully showed", %{conn: conn} do
      expect(MithrilMock, :get_user_by_id, fn user_id, _headers ->
        {:ok,
         %{
           "data" => %{
             "id" => user_id,
             "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
             "tax_id" => "12341234",
             "is_blocked" => false
           }
         }}
      end)

      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{"tax_id" => "12341234"})
      end)

      expect(OPSMock, :get_latest_block, fn _params ->
        {:ok, %{"data" => %{"hash" => "some_current_hash"}}}
      end)

      speciality = %{
        "speciality" => "PEDIATRICIAN",
        "speciality_officio" => true,
        "level" => "Перша категорія",
        "qualification_type" => "Підтвердження",
        "attestation_name" => "random string",
        "attestation_date" => ~D[1987-04-17],
        "valid_to_date" => ~D[1987-04-17],
        "certificate_number" => "random string"
      }

      %{id: employee_id} =
        insert(
          :prm,
          :employee,
          id: UUID.generate(),
          speciality: speciality
        )

      data =
        fixture_params()
        |> put_in(["employee", "id"], employee_id)

      %{id: declaration_request_id} = insert(:il, :declaration_request, mpi_id: @person_id, data: data)

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> get(cabinet_declaration_requests_path(conn, :show, declaration_request_id))

      assert %{
               "data" => %{
                 "seed" => "some_current_hash",
                 "employee" => %{
                   "speciality" => "PEDIATRICIAN"
                 }
               }
             } = json_response(conn, 200)
    end

    test "declaration request is not found", %{conn: conn} do
      expect(MithrilMock, :get_user_by_id, fn user_id, _headers ->
        {:ok,
         %{
           "data" => %{
             "id" => user_id,
             "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
             "tax_id" => "12341234",
             "is_blocked" => false
           }
         }}
      end)

      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{"tax_id" => "12341234"})
      end)

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> get(cabinet_declaration_requests_path(conn, :show, UUID.generate()))

      resp = json_response(conn, 404)
      assert %{"error" => %{"type" => "not_found"}} = resp
    end

    test "failed when declaration request is not belong to person", %{conn: conn} do
      expect(MithrilMock, :get_user_by_id, fn user_id, _headers ->
        {:ok,
         %{
           "data" => %{
             "id" => user_id,
             "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
             "tax_id" => "12341234",
             "is_blocked" => false
           }
         }}
      end)

      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{"tax_id" => "12341234"})
      end)

      %{id: declaration_request_id} = insert(:il, :declaration_request, data: fixture_params())

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> get(cabinet_declaration_requests_path(conn, :show, declaration_request_id))

      assert resp = json_response(conn, 403)
      assert %{"error" => %{"type" => "forbidden"}} = resp
    end

    test "failed when person is not valid", %{conn: conn} do
      expect(MithrilMock, :get_user_by_id, fn user_id, _headers ->
        {:ok,
         %{
           "data" => %{
             "id" => user_id,
             "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
             "tax_id" => "12341234",
             "is_blocked" => false
           }
         }}
      end)

      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{"tax_id" => "11111111"})
      end)

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> get(cabinet_declaration_requests_path(conn, :show, UUID.generate()))

      assert resp = json_response(conn, 401)
      assert %{"type" => "access_denied", "message" => "Person not found"} == resp["error"]
    end

    test "failed when user is blocked", %{conn: conn} do
      expect(MithrilMock, :get_user_by_id, fn user_id, _headers ->
        {:ok,
         %{
           "data" => %{
             "id" => user_id,
             "person_id" => "0c65d15b-32b4-4e82-b53d-0572416d890e",
             "tax_id" => "12341234",
             "is_blocked" => true
           }
         }}
      end)

      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{"tax_id" => "12341234"})
      end)

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> get(cabinet_declaration_requests_path(conn, :show, UUID.generate()))

      assert resp = json_response(conn, 401)
      assert %{"type" => "access_denied"} == resp["error"]
    end
  end

  describe "approve declaration_request" do
    test "success approve", %{conn: conn} do
      expect(MPIMock, :person, fn id, _headers ->
        get_person(id, 200, %{tax_id: "12341234"})
      end)

      expect(OPSMock, :get_declarations_count, fn _, _ ->
        {:ok, %{"data" => %{"count" => 10}}}
      end)

      declaration_request =
        insert(
          :il,
          :declaration_request,
          channel: DeclarationRequest.channel(:cabinet),
          mpi_id: "0c65d15b-32b4-4e82-b53d-0572416d890e"
        )

      insert(:prm, :employee, id: "d290f1ee-6c54-4b01-90e6-d701748f0851")

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> patch(cabinet_declaration_requests_path(conn, :approve, declaration_request.id))

      assert resp = json_response(conn, 200)
      assert DeclarationRequest.status(:approved) == resp["data"]["status"]
    end

    test "wrong channel", %{conn: conn} do
      declaration_request =
        insert(
          :il,
          :declaration_request,
          channel: DeclarationRequest.channel(:mis)
        )

      conn =
        conn
        |> put_consumer_id_header(@user_id)
        |> put_client_id_header(@user_id)
        |> patch(cabinet_declaration_requests_path(conn, :approve, declaration_request.id))

      assert resp = json_response(conn, 403)
      assert "Declaration request should be approved by Doctor" == resp["error"]["message"]
    end
  end

  defp fixture_params(params \\ %{}) do
    %{
      "scope" => "family_doctor",
      "person" => %{
        "id" => UUID.generate(),
        "email" => nil,
        "gender" => "MALE",
        "secret" => "тЕСТдоК",
        "tax_id" => "3173108921",
        "phones" => [%{"type" => "MOBILE", "number" => "+380503410870"}],
        "addresses" => [
          %{
            "zip" => "21236",
            "area" => "АВТОНОМНА РЕСПУБЛІКА КРИМ",
            "type" => "RESIDENCE",
            "street" => "Тест",
            "country" => "UA",
            "building" => "1",
            "apartment" => "2",
            "settlement" => "ВОЛОШИНЕ",
            "street_type" => "STREET",
            "settlement_id" => UUID.generate(),
            "settlement_type" => "VILLAGE"
          },
          %{
            "zip" => "21236",
            "area" => "АВТОНОМНА РЕСПУБЛІКА КРИМ",
            "type" => "REGISTRATION",
            "street" => "Тест",
            "country" => "UA",
            "building" => "1",
            "apartment" => "2",
            "settlement" => "ВОЛОШИНЕ",
            "street_type" => "STREET",
            "settlement_id" => UUID.generate(),
            "settlement_type" => "VILLAGE"
          }
        ],
        "documents" => [%{"type" => "TEMPORARY_CERTIFICATE", "number" => "тт260656"}],
        "last_name" => "Петров",
        "birth_date" => "1991-08-20",
        "first_name" => "Іван",
        "second_name" => "Миколайович",
        "birth_country" => "Україна",
        "patient_signed" => false,
        "birth_settlement" => "Киев",
        "confidant_person" => [
          %{
            "gender" => "MALE",
            "phones" => [%{"type" => "MOBILE", "number" => "+380503410870"}],
            "secret" => "secret",
            "tax_id" => "3378115538",
            "last_name" => "Іванов",
            "birth_date" => "1991-08-19",
            "first_name" => "Петро",
            "second_name" => "Миколайович",
            "birth_country" => "Україна",
            "relation_type" => "PRIMARY",
            "birth_settlement" => "Вінниця",
            "documents_person" => [%{"type" => "PASSPORT", "number" => "120518"}],
            "documents_relationship" => [
              %{"type" => "COURT_DECISION", "number" => "120518"}
            ]
          },
          %{
            "gender" => "MALE",
            "phones" => [%{"type" => "MOBILE", "number" => "+380503410870"}],
            "secret" => "secret",
            "tax_id" => "3378115538",
            "last_name" => "Іванов",
            "birth_date" => "1991-08-19",
            "first_name" => "Петро",
            "second_name" => "Миколайович",
            "birth_country" => "Україна",
            "relation_type" => "SECONDARY",
            "birth_settlement" => "Вінниця",
            "documents_person" => [%{"type" => "PASSPORT", "number" => "120518"}],
            "documents_relationship" => [
              %{"type" => "COURT_DECISION", "number" => "120518"}
            ]
          }
        ],
        "emergency_contact" => %{
          "phones" => [%{"type" => "MOBILE", "number" => "+380686521488"}],
          "last_name" => "ТестДит",
          "first_name" => "ТестДит",
          "second_name" => "ТестДит"
        },
        "authentication_methods" => [%{"type" => "OFFLINE"}],
        "process_disclosure_data_consent" => true
      },
      "channel" => "MIS",
      "division" => %{
        "id" => UUID.generate(),
        "name" => "Бориспільське відділення Клініки Борис",
        "type" => "CLINIC",
        "status" => "ACTIVE",
        "email" => "example@gmail.com",
        "phones" => [%{"type" => "MOBILE", "number" => "+380503410870"}],
        "addresses" => [
          %{
            "zip" => "43000",
            "area" => "М.КИЇВ",
            "type" => "RESIDENCE",
            "street" => "Шевченка",
            "country" => "UA",
            "building" => "2",
            "apartment" => "23",
            "settlement" => "КИЇВ",
            "street_type" => "STREET",
            "settlement_id" => UUID.generate(),
            "settlement_type" => "CITY"
          }
        ],
        "external_id" => "3213213",
        "legal_entity_id" => UUID.generate()
      },
      "employee" => %{
        "id" => UUID.generate(),
        "party" => %{
          "id" => UUID.generate(),
          "email" => "example309@gmail.com",
          "phones" => [%{"type" => "MOBILE", "number" => "+380503410870"}],
          "tax_id" => "3033413670",
          "last_name" => "Іванов",
          "first_name" => "Петро",
          "second_name" => "Миколайович"
        },
        "position" => "P2",
        "status" => "APPROVED",
        "start_date" => "2017-03-02T10:45:16.000Z",
        "legal_entity_id" => UUID.generate()
      },
      "end_date" => "2068-06-12",
      "start_date" => "2018-06-12",
      "legal_entity" => %{
        "id" => UUID.generate(),
        "name" => "Клініка Лимич Медікал",
        "email" => "lymychcl@gmail.com",
        "edrpou" => "3160405192",
        "phones" => [%{"type" => "MOBILE", "number" => "+380979134223"}],
        "licenses" => [
          %{
            "order_no" => "К-123",
            "issued_by" => "Кваліфікацйна комісія",
            "expiry_date" => "1991-08-19",
            "issued_date" => "1991-08-19",
            "what_licensed" => "реалізація наркотичних засобів",
            "license_number" => "fd123443",
            "active_from_date" => "1991-08-19"
          }
        ],
        "addresses" => [
          %{
            "zip" => "02090",
            "area" => "ХАРКІВСЬКА",
            "type" => "REGISTRATION",
            "street" => "вул. Ніжинська",
            "country" => "UA",
            "building" => "15",
            "apartment" => "23",
            "settlement" => "ЧУГУЇВ",
            "street_type" => "STREET",
            "settlement_id" => UUID.generate(),
            "settlement_type" => "CITY"
          }
        ],
        "legal_form" => "140",
        "short_name" => "Лимич Медікал",
        "public_name" => "Лимич Медікал",
        "status" => "ACTIVE",
        "accreditation" => %{
          "category" => "FIRST",
          "order_no" => "fd123443",
          "order_date" => "1991-08-19",
          "expiry_date" => "1991-08-19",
          "issued_date" => "1991-08-19"
        }
      },
      "declaration_id" => UUID.generate(),
      "status" => "NEW"
    }
    |> Map.merge(params)
  end

  defp get_person(id, response_status, params) do
    params = Map.put(params, :id, id)
    person = string_params_for(:person, params)

    {:ok, %{"data" => person, "meta" => %{"code" => response_status}}}
  end

  defp get_person_addresses do
    [
      build(:address, %{"type" => "REGISTRATION"}),
      build(:address, %{"type" => "RESIDENCE"})
    ]
  end
end
