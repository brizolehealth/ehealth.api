defmodule Core.Validators.Preload do
  @moduledoc false

  alias Core.Validators.Reference

  def preload_references_for_list(entities, fields) when is_list(entities) do
    entities
    |> Enum.map(fn item ->
      Enum.reduce(fields, %{}, &get_reference_id(item, &1, &2))
    end)
    |> Enum.reduce(%{}, fn item_references, acc ->
      Map.merge(item_references, acc, fn _k, refs_1, refs_2 ->
        Enum.uniq(refs_1 ++ refs_2)
      end)
    end)
    |> load_references()
  end

  def preload_references(%{} = item, fields) do
    fields
    |> Enum.reduce(%{}, &get_reference_id(item, &1, &2))
    |> load_references()
  end

  def preload_references(nil, _), do: %{}

  defp load_references(item_references) do
    item_references
    |> Enum.into(%{}, fn {type, ids} ->
      {type,
       Enum.into(ids, %{}, fn id ->
         with {:ok, value} <- Reference.validate(type, id) do
           {id, value}
         else
           _ -> {id, nil}
         end
       end)}
    end)
  end

  defp get_reference_id(item, {field_path, type}, acc) when is_atom(field_path) or is_binary(field_path) do
    do_get_reference_id(Map.get(item, field_path), type, acc)
  end

  defp get_reference_id(item, {[field_path], type}, acc) when is_atom(field_path) or is_binary(field_path) do
    do_get_reference_id(Map.get(item, field_path), type, acc)
  end

  defp get_reference_id(item, {field_path, type}, acc) when is_list(field_path) do
    [path | tail_path] = field_path

    case path do
      "$" ->
        if is_nil(item) do
          acc
        else
          Enum.reduce(item, acc, fn list_item, acc ->
            get_reference_id(list_item, {tail_path, type}, acc)
          end)
        end

      _ ->
        get_reference_id(Map.get(item, path), {tail_path, type}, acc)
    end
  end

  defp do_get_reference_id(nil, _, acc), do: acc

  defp do_get_reference_id(reference_id, type, acc) when is_binary(reference_id) do
    ids = Map.get(acc, type) || []
    ids = if Enum.member?(ids, reference_id) || is_nil(reference_id), do: ids, else: [reference_id | ids]
    Map.put(acc, type, ids)
  end

  defp do_get_reference_id(reference_ids, type, map) when is_list(reference_ids) do
    Enum.reduce(reference_ids, map, fn id, acc ->
      ids = Map.get(acc, type) || []
      ids = if Enum.member?(ids, id) || is_nil(id), do: ids, else: [id | ids]
      Map.put(acc, type, ids)
    end)
  end
end
