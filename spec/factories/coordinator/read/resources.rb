# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_resource, class: "Coordinator::Read::Resource" do
    resource_id { SecureRandom.uuid_v7 }
    repository_id { SecureRandom.uuid_v7 }
    kind { "file" }
    sequence(:normalized_path) { "app/models/factory_#{_1}.rb" }
    lifecycle_status { "current" }
    registered_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "ResourceRegistered",
        "stream_context" => "DevelopmentCoordination",
        "stream_name" => "Resource",
        "stream_id" => resource_id,
        "stream_revision" => 0
      }
    end
    registered_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    registered_markers { [ "resource:#{resource_id}" ] }
    registered_metadata { { "schema_version" => 2 } }
    sequence(:registered_global_position, 300)
    registered_at_domain { Time.utc(2026, 8, 30, 12) }
    registered_at_store { registered_at_domain }
    latest_transition_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "ResourceBound",
        "stream_context" => "DevelopmentCoordination",
        "stream_name" => "Resource",
        "stream_id" => resource_id,
        "stream_revision" => 1
      }
    end
    latest_transition_actor { registered_actor }
    latest_transition_markers { registered_markers }
    latest_transition_metadata { { "schema_version" => 2 } }
    sequence(:latest_transition_global_position, 400)
    latest_transition_at_domain { Time.utc(2026, 8, 30, 12, 1) }
    latest_transition_at_store { latest_transition_at_domain }

    trait :inactive do
      lifecycle_status { "inactive" }
      unbinding_reason { "removed" }
      latest_transition_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "ResourceUnbound",
          "stream_context" => "DevelopmentCoordination",
          "stream_name" => "Resource",
          "stream_id" => resource_id,
          "stream_revision" => 2
        }
      end
    end
  end
end
