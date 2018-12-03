defmodule Core.Repo.Migrations.CreateDeactivateLegalEntityEventTopic do
  use Ecto.Migration

  def change do
    Application.ensure_all_started(:kafka_ex)
    partitions = Confex.fetch_env!(:core, :kafka)[:partitions]
    topic = "deactivate_legal_entity_event"

    request = %{
      topic: topic,
      num_partitions: partitions,
      replication_factor: 1,
      replica_assignment: [],
      config_entries: []
    }

    KafkaEx.create_topics([request], timeout: 2000)
  end
end
