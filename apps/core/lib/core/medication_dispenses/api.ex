defmodule Core.MedicationDispense.API do
  @moduledoc false

  import Core.API.Helpers.Connection, only: [get_client_id: 1, get_consumer_id: 1]
  import Ecto.Changeset, only: [cast: 3]
  import Ecto.Query
  require Logger

  alias Core.Contracts.ReimbursementContract
  alias Core.Divisions
  alias Core.Divisions.Division
  alias Core.Employees
  alias Core.Employees.Employee
  alias Core.LegalEntities
  alias Core.LegalEntities.LegalEntity
  alias Core.MedicalPrograms
  alias Core.MedicationDispense.Renderer, as: MedicationDispenseRenderer
  alias Core.MedicationDispenses.Search
  alias Core.MedicationDispenses.SearchByMedicationRequest
  alias Core.MedicationRequests.API, as: MedicationRequests
  alias Core.MedicationRequests.MedicationRequest
  alias Core.Medications
  alias Core.Medications.Medication
  alias Core.Medications.Program, as: ProgramMedication
  alias Core.Parties
  alias Core.Parties.Party
  alias Core.PartyUsers
  alias Core.PartyUsers.PartyUser
  alias Core.PRMRepo
  alias Core.ValidationError
  alias Core.Validators.Content, as: ContentValidator
  alias Core.Validators.Error
  alias Core.Validators.JsonSchema
  alias Core.Validators.Reference
  alias Core.Validators.Signature, as: SignatureValidator

  use Confex, otp_app: :core

  @ops_api Application.get_env(:core, :api_resolvers)[:ops]
  @media_storage_api Application.get_env(:core, :api_resolvers)[:media_storage]

  @intent_order MedicationRequest.intent(:order)
  @reimbursement_contract_status_verified ReimbursementContract.status(:verified)

  @search_fields ~w(
    id
    medication_request_id
    legal_entity_id
    division_id
    status
    dispensed_from
    dispensed_to
    page
    page_size
  )a

  @search_by_medication_request_fields ~w(
    medication_request_id
    legal_entity_id
    status
    page
    page_size
  )a

  def list(params, headers) do
    with %Ecto.Changeset{valid?: true, changes: changes} <- changeset(%Search{}, params),
         params <- Map.put(changes, "is_active", true),
         {:ok, %{"data" => medication_dispenses, "paging" => paging}} <-
           @ops_api.get_medication_dispenses(params, headers),
         {:ok, medication_dispenses} <- get_medication_request_references(medication_dispenses),
         {:ok, medication_dispenses} <- load_dispenses_medications(medication_dispenses) do
      {:ok, medication_dispenses, get_references(medication_dispenses), paging}
    end
  end

  def list_by_medication_request(%{"id" => id} = params, headers) do
    with params <- Map.put(params, "medication_request_id", id),
         params <- Map.delete(params, "id"),
         %Ecto.Changeset{valid?: true, changes: changes} <- changeset(%SearchByMedicationRequest{}, params),
         dispense_filters <- Map.delete(changes, :legal_entity_id),
         {:ok, %{"data" => medication_dispenses}} <- @ops_api.get_medication_dispenses(dispense_filters, headers),
         {:ok, medication_dispenses} <- get_medication_request_references(medication_dispenses),
         {:ok, medication_dispenses} <- load_dispenses_medications(medication_dispenses) do
      {:ok, medication_dispenses, get_references(medication_dispenses)}
    end
  end

  def get_by_id(params, headers) do
    legal_entity_id = Map.get(params, "legal_entity_id")
    search_params = Map.delete(params, "legal_entity_id")

    with {:ok, %{"data" => [medication_dispense]}} <- @ops_api.get_medication_dispenses(search_params, headers),
         {:ok, legal_entity} <- Reference.validate(:legal_entity, medication_dispense["legal_entity_id"]),
         {:ok, details} <- load_dispense_medications(medication_dispense),
         medication_dispense <- Map.put(medication_dispense, "details", details),
         {:ok, party} <- get_party_by_id(medication_dispense["party_id"]),
         :ok <- validate_legal_entity_id(medication_dispense, legal_entity_id),
         division <- Divisions.get_by_id(medication_dispense["division_id"]),
         medical_program <- MedicalPrograms.get_by_id(medication_dispense["medical_program_id"]),
         medication_request <- medication_dispense["medication_request"],
         {:ok, medication_request} <- MedicationRequests.get_references(medication_request) do
      {:ok, medication_dispense,
       %{
         legal_entity: legal_entity,
         division: division,
         medication_request: medication_request,
         medical_program: medical_program,
         party: party
       }}
    else
      {:error, {:internal_error, reason}} -> {:error, {:internal_error, reason}}
      _ -> nil
    end
  end

  def create(headers, client_type, code, params) do
    legal_entity_id = get_client_id(headers)
    user_id = get_consumer_id(headers)

    with :ok <- JsonSchema.validate(:medication_dispense, params),
         params <- params["medication_dispense"],
         {:ok, legal_entity} <- Reference.validate(:legal_entity, legal_entity_id),
         {:ok, party_user} <- get_party_user(user_id),
         :ok <- validate_legal_entity(legal_entity),
         {:ok, medication_request} <- validate_medication_request(params["medication_request_id"]),
         {:intent, @intent_order} <- {:intent, medication_request["intent"]},
         :ok <- validate_employee(party_user, legal_entity_id),
         {:ok, division} <- validate_division(params["division_id"], legal_entity_id),
         {:ok, medical_program} <-
           validate_medical_program(params["medical_program_id"], medication_request, legal_entity_id),
         details <- params["dispense_details"],
         {:ok, dispense_details, medications} <- validate_medications(details, medical_program),
         :ok <- validate_code(code, medication_request),
         :ok <- qualify_request(medication_request, client_type, headers),
         :ok <- check_other_medication_dispenses(medication_request, headers),
         :ok <- check_medication_qty(params, medication_request),
         :ok <- check_medication_multiplicity(dispense_details, medications),
         create_params <- Map.put(params, "dispense_details", dispense_details),
         create_params <- Map.put(create_params, "legal_entity_id", legal_entity.id),
         create_params <- create_dispense_params(create_params, user_id, party_user.party),
         {:ok, %{"data" => medication_dispense}} <- @ops_api.create_medication_dispense(create_params, []),
         {:ok, details} <- load_dispense_medications(medication_dispense),
         medication_dispense <- Map.put(medication_dispense, "details", details) do
      {:ok, medication_dispense,
       %{
         legal_entity: legal_entity,
         division: division,
         medication_request: medication_request,
         medical_program: medical_program,
         party: party_user.party
       }}
    else
      {:intent, _} -> {:error, {:conflict, "Medication request with intent PLAN cannot be dispensed"}}
      err -> err
    end
  end

  def process(%{"id" => id} = params, headers) do
    user_id = get_consumer_id(headers)
    legal_entity_id = get_client_id(headers)

    request_attrs = %{
      "status" => "COMPLETED",
      "updated_by" => user_id
    }

    with :ok <- JsonSchema.validate(:medication_dispense_process, params),
         {:ok, medication_dispense, references} <-
           get_by_id(Map.drop(params, ~w(signed_medication_dispense signed_content_encoding)), headers),
         {:ok, %{"content" => content, "signers" => [signer]}} <- decode_signed_content(params, headers),
         :ok <- SignatureValidator.check_drfo(signer, user_id, "medication_dispense_process"),
         :ok <- SignatureValidator.check_last_name(signer, user_id),
         :ok <- SignatureValidator.check_legal_entity_edrpou(signer, legal_entity_id),
         :ok <- validate_status_transition(medication_dispense, "PROCESSED"),
         :ok <- JsonSchema.validate(:medication_dispense_process_content, content),
         :ok <- compare_with_db(content, medication_dispense, references),
         :ok <- save_signed_content(id, params, headers),
         attrs <-
           content
           |> Map.take(~w(payment_id payment_amount))
           |> Map.merge(%{
             "status" => "PROCESSED",
             "updated_by" => user_id
           }),
         {:ok, %{"data" => medication_dispense}} <-
           @ops_api.update_medication_dispense(id, %{"medication_dispense" => attrs}, headers),
         {:ok, details} <- load_dispense_medications(medication_dispense),
         medication_dispense <- Map.put(medication_dispense, "details", details),
         medication_request_id <- Map.get(references.medication_request, "id"),
         {:ok, _} <-
           @ops_api.update_medication_request(medication_request_id, %{"medication_request" => request_attrs}, headers) do
      {:ok, medication_dispense, references}
    end
  end

  def reject(%{"id" => id} = params, headers) do
    attrs =
      params
      |> Map.take(~w(payment_id))
      |> Map.put("status", "REJECTED")
      |> Map.put("updated_by", get_consumer_id(headers))

    with {:ok, medication_dispense, references} <- get_by_id(params, headers),
         :ok <- validate_status_transition(medication_dispense, "REJECTED"),
         {:ok, %{"data" => medication_dispense}} <-
           @ops_api.update_medication_dispense(id, %{"medication_dispense" => attrs}, headers) do
      {:ok, medication_dispense, references}
    end
  end

  def decode_signed_content(
        %{"signed_medication_dispense" => signed_content, "signed_content_encoding" => encoding},
        headers
      ) do
    SignatureValidator.validate(signed_content, encoding, headers)
  end

  defp compare_with_db(content, medication_dispense, references) do
    db_content =
      "show.json"
      |> MedicationDispenseRenderer.render(medication_dispense, references)
      |> Jason.encode!()
      |> Jason.decode!()
      |> Map.drop(~w(payment_id payment_amount))

    content = Map.drop(content, ~w(payment_id payment_amount))
    ContentValidator.compare_with_db(content, db_content, "medication_dispense_process")
  end

  defp save_signed_content(id, %{"signed_medication_dispense" => signed_content}, headers) do
    signed_content
    |> @media_storage_api.store_signed_content(
      :medication_dispense_bucket,
      id,
      "medication_dispense_process",
      headers
    )
    |> case do
      {:ok, _} -> :ok
      _error -> {:error, {:bad_gateway, "Failed to save signed content"}}
    end
  end

  defp validate_legal_entity(%LegalEntity{} = legal_entity) do
    with :ok <- validate_legal_entity_status(legal_entity),
         :ok <- validate_legal_entity_mis_verified(legal_entity) do
      :ok
    end
  end

  defp validate_legal_entity_status(%LegalEntity{is_active: is_active, status: status}) do
    if is_active && status == LegalEntity.status(:active) do
      :ok
    else
      {:conflict, "Legal entity is not active"}
    end
  end

  defp validate_legal_entity_mis_verified(%LegalEntity{mis_verified: mis_verified}) do
    if mis_verified == LegalEntity.mis_verified(:verified) do
      :ok
    else
      {:conflict, "Legal entity is not verified"}
    end
  end

  defp validate_medication_request(id) do
    with {:ok, medication_request} <- Reference.validate(:medication_request, id),
         :ok <- is_active_medication_request(medication_request),
         :ok <- validate_medication_request_period(medication_request),
         {:ok, medication_request} <- MedicationRequests.get_references(medication_request) do
      {:ok, medication_request}
    end
  end

  defp validate_employee(%PartyUser{party: %Party{id: party_id}}, legal_entity_id) do
    employees = Employees.list(%{party_id: party_id})

    Enum.reduce_while(employees, {:error, {:forbidden, "Employee id doesn't match"}}, fn employee, acc ->
      if is_active_employee(employee) && employee.legal_entity_id == legal_entity_id do
        {:halt, :ok}
      else
        {:cont, acc}
      end
    end)
  end

  defp validate_division(id, legal_entity_id) do
    with {:ok, division} <- Reference.validate(:division, id),
         true <- is_active_division(division) && division.legal_entity_id == legal_entity_id do
      {:ok, division}
    else
      false -> {:conflict, "Division is not active"}
      err -> err
    end
  end

  defp validate_medical_program(id, medication_request, legal_entity_id) do
    is_active = fn medical_program ->
      {:is_active, medical_program.is_active}
    end

    is_matched = fn medical_program ->
      {:is_matched, medical_program.id == Map.get(medication_request, "medical_program_id")}
    end

    with {:ok, medical_program} <- Reference.validate(:medical_program, id),
         {:is_active, true} <- is_active.(medical_program),
         {:is_matched, true} <- is_matched.(medical_program),
         :ok <- validate_contract(id, legal_entity_id) do
      {:ok, medical_program}
    else
      {:is_active, false} ->
        {:conflict, "Medical program is not active"}

      {:is_matched, false} ->
        Error.dump(%ValidationError{
          description: "Medical program in dispense doesn't match the one in medication request",
          path: "$.medical_program_id"
        })

      err ->
        err
    end
  end

  defp validate_contract(medical_program_id, legal_entity_id) do
    case get_valid_reimbursement_contract(medical_program_id, legal_entity_id) do
      %ReimbursementContract{} -> :ok
      _ -> {:conflict, "Program cannot be used - no active contract exists"}
    end
  end

  defp get_valid_reimbursement_contract(medical_program_id, legal_entity_id) do
    ReimbursementContract
    |> where(
      [c],
      c.status == @reimbursement_contract_status_verified and c.contractor_legal_entity_id == ^legal_entity_id and
        c.medical_program_id == ^medical_program_id
    )
    |> PRMRepo.one()
  end

  defp validate_medications(dispense_details, %{id: medical_program_id}) do
    result =
      dispense_details
      |> Enum.with_index()
      |> Enum.map(fn {%{"medication_id" => id} = item, i} ->
        with {:ok, medication} <- Reference.validate(:medication, id, "$.dispense_details[#{i}].medication_id"),
             :ok <- validate_active_medication(medication, i),
             {:ok, program_medication} <- get_active_program_medication(id, medical_program_id, i),
             reimbursement_amount <- program_medication.reimbursement["reimbursement_amount"],
             :ok <- validate_reimbursement_amount(reimbursement_amount, item, medication, i) do
          {:ok, Map.put(item, "reimbursement_amount", reimbursement_amount), medication}
        end
      end)

    errors =
      Enum.reduce(result, [], fn
        {:error, [err]}, acc -> [err | acc]
        _, acc -> acc
      end)

    details =
      Enum.reduce(result, [], fn
        {:ok, dispense_details, _}, acc -> [dispense_details | acc]
        _, acc -> acc
      end)

    medications =
      result
      |> Enum.map(fn
        {:ok, _, medication} -> medication
        _ -> nil
      end)
      |> Enum.filter(&Kernel.!(is_nil(&1)))

    if Enum.empty?(errors), do: {:ok, details, medications}, else: {:error, errors}
  end

  defp get_active_program_medication(medication_id, medical_program_id, i) do
    program_medication =
      ProgramMedication
      |> where([pm], pm.is_active)
      |> where([pm], pm.medication_id == ^medication_id)
      |> where([pm], pm.medical_program_id == ^medical_program_id)
      |> limit(1)
      |> PRMRepo.one()

    if is_nil(program_medication) do
      Error.dump(%ValidationError{
        description: "medication is not a participant of program",
        path: "$.dispense_details[#{i}].medication_id"
      })
    else
      {:ok, program_medication}
    end
  end

  defp validate_reimbursement_amount(reimbursement_amount, details, medication, i) do
    %{"medication_qty" => medication_qty, "discount_amount" => discount_amount} = details

    deviation = config()[:deviation]
    coefficient = discount_amount / (reimbursement_amount / medication.package_qty * medication_qty)

    if 1 >= coefficient and coefficient >= 1 - deviation do
      :ok
    else
      Error.dump(%ValidationError{
        description: "Requested discount price does not satisfy allowed reimbursement amount",
        path: "$.dispense_details[#{i}].discount_amount",
        rule: :required
      })
    end
  end

  defp validate_active_medication(%Medication{} = medication, i) do
    ingredient = Enum.find(medication.ingredients, &Map.get(&1, :is_primary))

    if medication.is_active && ingredient do
      :ok
    else
      Error.dump(%ValidationError{
        description: "medication is not active",
        path: "$.dispense_details[#{i}].medication_id",
        rule: :required
      })
    end
  end

  defp validate_code(nil, %{"verification_code" => nil}), do: :ok
  defp validate_code(_, %{"verification_code" => nil}), do: {:error, {:access_denied, "Incorrect code"}}

  defp validate_code(code, %{"verification_code" => verification_code}) do
    if code == verification_code do
      :ok
    else
      {:error, {:access_denied, "Incorrect code"}}
    end
  end

  defp check_other_medication_dispenses(%{"id" => medication_request_id}, headers) do
    params = %{"status" => "NEW,PROCESSED", "medication_request_id" => medication_request_id}

    with {:ok, %{"data" => []}} <- @ops_api.get_medication_dispenses(params, headers) do
      :ok
    else
      _ -> {:error, {:forbidden, "Active medication dispense already exists"}}
    end
  end

  defp check_medication_qty(%{"dispense_details" => details}, medication_request) do
    request_qty =
      Enum.reduce(details, 0, fn item, acc ->
        acc + Map.get(item, "medication_qty")
      end)

    if request_qty <= Map.get(medication_request, "medication_qty") do
      :ok
    else
      Error.dump(%ValidationError{
        description: "dispensed medication quantity must be less or equal to medication quantity in Medication Request",
        path: "$.medication_request.medication_qty",
        rule: :required
      })
    end
  end

  defp is_active_medication_request(medication_request) do
    now = Date.utc_today()
    started_at = Date.from_iso8601!(Map.get(medication_request, "started_at"))
    ended_at = Date.from_iso8601!(Map.get(medication_request, "ended_at"))
    is_active = Map.get(medication_request, "is_active")
    status = Map.get(medication_request, "status")
    is_valid_period = Date.compare(started_at, now) != :gt && Date.compare(ended_at, now) != :lt

    if is_active and status == "ACTIVE" && is_valid_period do
      :ok
    else
      {:conflict, "Medication request is not active"}
    end
  end

  defp is_active_employee(employee) do
    employee.is_active && employee.status == Employee.status(:approved)
  end

  defp is_active_division(division) do
    division.is_active && division.status == Division.status(:active)
  end

  defp validate_medication_request_period(medication_request) do
    from =
      medication_request
      |> Map.get("dispense_valid_from")
      |> Date.from_iso8601!()

    to =
      medication_request
      |> Map.get("dispense_valid_to")
      |> Date.from_iso8601!()

    now = Date.utc_today()

    if Date.compare(from, now) != :gt && Date.compare(to, now) != :lt do
      :ok
    else
      {:conflict, "Invalid dispense period"}
    end
  end

  defp changeset(%Search{} = search, attrs) do
    cast(search, attrs, @search_fields)
  end

  defp changeset(%SearchByMedicationRequest{} = search, attrs) do
    cast(search, attrs, @search_by_medication_request_fields)
  end

  defp get_references(medication_dispenses) do
    reference_ids = %{
      division_ids: [],
      legal_entity_ids: [],
      party_ids: [],
      medical_program_ids: [],
      medication_ids: []
    }

    reference_ids =
      Enum.reduce(medication_dispenses, reference_ids, fn medication_dispense, acc ->
        medication_ids = Enum.map(medication_dispense["details"], &Map.get(&1, "medication_id"))

        %{
          acc
          | division_ids: [medication_dispense["division_id"] | acc.division_ids],
            legal_entity_ids: [medication_dispense["legal_entity_id"] | acc.legal_entity_ids],
            party_ids: [medication_dispense["party_id"] | acc.party_ids],
            medical_program_ids: [medication_dispense["medical_program_id"] | acc.medical_program_ids],
            medication_ids: acc.medication_ids ++ medication_ids
        }
      end)

    divisions =
      reference_ids.division_ids
      |> Divisions.get_by_ids()
      |> Enum.into(%{}, &{Map.get(&1, :id), &1})

    legal_entities =
      reference_ids.legal_entity_ids
      |> LegalEntities.get_by_ids()
      |> Enum.into(%{}, &{Map.get(&1, :id), &1})

    parties =
      reference_ids.party_ids
      |> Parties.get_by_ids()
      |> Enum.into(%{}, &{Map.get(&1, :id), &1})

    medical_programs =
      reference_ids.medical_program_ids
      |> MedicalPrograms.get_by_ids()
      |> Enum.into(%{}, &{Map.get(&1, :id), &1})

    medications =
      reference_ids.medication_ids
      |> Medications.get_by_ids()
      |> Enum.into(%{}, &{Map.get(&1, :id), &1})

    %{
      divisions: divisions,
      legal_entities: legal_entities,
      parties: parties,
      medical_programs: medical_programs,
      medications: medications
    }
  end

  defp validate_legal_entity_id(_, nil), do: :ok

  defp validate_legal_entity_id(medication_dispense, legal_entity_id) do
    if medication_dispense["legal_entity_id"] == legal_entity_id do
      :ok
    else
      {:error, {:forbidden, "Legal Entity id doesn't match"}}
    end
  end

  defp validate_status_transition(%{"status" => from_status}, to_status) do
    transitions = [
      {"NEW", "PROCESSED"},
      {"NEW", "REJECTED"},
      {"NEW", "EXPIRED"}
    ]

    is_valid_transition =
      Enum.find(transitions, fn {from, to} ->
        from == from_status && to == to_status
      end)

    if is_valid_transition do
      :ok
    else
      {:conflict, "Can't update medication dispense status from #{from_status} to #{to_status}"}
    end
  end

  defp check_medication_multiplicity(dispense_details, medications) do
    errors =
      dispense_details
      |> Enum.with_index()
      |> Enum.map(fn {request_medication, i} ->
        medication = Enum.find(medications, &(Map.get(&1, :id) == request_medication["medication_id"]))

        if rem(request_medication["medication_qty"], medication.package_min_qty) == 0 do
          :ok
        else
          Error.dump(%ValidationError{
            description: "Requested medication brand quantity must be a multiplier of package minimal quantity",
            path: "$.dispense_details[#{i}].medication_qty",
            rule: :required
          })
        end
      end)
      |> Enum.filter(&(&1 != :ok))

    if Enum.empty?(errors) do
      :ok
    else
      {:error,
       errors
       |> Enum.map(&elem(&1, 1))
       |> Enum.concat()}
    end
  end

  defp get_party_user(user_id) do
    case PartyUsers.list!(%{user_id: user_id}) do
      [] -> {:error, {:bad_request, "Party not found"}}
      [party_user] -> {:ok, party_user}
    end
  end

  defp get_party_by_id(id) do
    with %Party{} = party <- Parties.get_by_id(id) do
      {:ok, party}
    else
      nil -> {:error, {:internal_error, "No party by id #{id}"}}
    end
  end

  defp get_medication_request_references(medication_dispenses) do
    result =
      Enum.reduce_while(medication_dispenses, [], fn dispense, acc ->
        medication_request = dispense["medication_request"]

        with {:ok, medication_request} <- MedicationRequests.get_references(medication_request) do
          {:cont, acc ++ [%{dispense | "medication_request" => medication_request}]}
        else
          error -> {:halt, error}
        end
      end)

    if is_list(result), do: {:ok, result}, else: result
  end

  defp create_dispense_params(params, user_id, %Party{id: party_id}) do
    medication_dispense =
      params
      |> Map.put("id", Ecto.UUID.generate())
      |> Map.put("inserted_by", user_id)
      |> Map.put("updated_by", user_id)
      |> Map.put("status", "NEW")
      |> Map.put("is_active", true)
      |> Map.put("party_id", party_id)

    %{"medication_dispense" => medication_dispense}
  end

  defp load_dispenses_medications(medication_dispenses) do
    Enum.reduce_while(medication_dispenses, {:ok, []}, fn medication_dispense, {:ok, acc} ->
      with {:ok, details} <- load_dispense_medications(medication_dispense) do
        {:cont, {:ok, acc ++ [Map.put(medication_dispense, "details", details)]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp load_dispense_medications(%{"details" => details}) do
    Enum.reduce_while(details, {:ok, []}, fn item, {:ok, acc} ->
      with %Medication{} = medication <- Medications.get_medication_by_id(Map.get(item, "medication_id")) do
        {:cont, {:ok, acc ++ [Map.put(item, "medication", medication)]}}
      else
        _ -> {:halt, {:error, {:internal_error, "Medication not found"}}}
      end
    end)
  end

  defp qualify_request(medication_request, client_type, headers) do
    program_id = medication_request["medical_program_id"]
    params = %{"programs" => [%{"id" => program_id}]}

    case MedicationRequests.qualify(medication_request["id"], client_type, params, headers) do
      {:ok, _, %{^program_id => :ok}} ->
        :ok

      _ ->
        {:conflict,
         "Medication request can not be dispensed. " <> "Invoke qualify medication request API to get detailed info"}
    end
  end
end
