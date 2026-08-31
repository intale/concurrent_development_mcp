# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_attempt_history, class: "Coordinator::Read::AttemptHistory" do
    sequence(:attempt_id) { "attempt-#{_1}" }
    sequence(:change_set_id) { "change-set-#{_1}" }
    sequence(:work_item_id) { "work-item-#{_1}" }
    sequence(:authorized_global_position, 1)

    agent_id { "factory-agent" }
    base_snapshots do
      [
        {
          "repository_id" => SecureRandom.uuid_v7,
          "object_format" => "sha1",
          "commit_oid" => "a" * 40
        }
      ]
    end
    status { "authorized" }
    authorization_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "AttemptAuthorized",
        "stream_context" => "DevelopmentCoordination",
        "stream_name" => "Attempt",
        "stream_id" => attempt_id,
        "stream_revision" => 0
      }
    end
    authorized_at_domain { Time.utc(2026, 8, 30, 12) }

    trait :with_write_set do
      transient do
        write_set_resource_id { SecureRandom.uuid_v7 }
        write_set_resource_kind { "file" }
        write_set_resource_path { "app/models/factory_lease.rb" }
        write_set_lease_id { SecureRandom.uuid_v7 }
      end

      write_set_lease_set_id { SecureRandom.uuid_v7 }
      write_set_repository_id { base_snapshots.sole.fetch("repository_id") }
      write_set_policy_version { "coordinator-resource-lease/v2" }
      write_set_resources do
        [
          {
            "lease_id" => write_set_lease_id,
            "resource_id" => write_set_resource_id,
            "resource_kind" => write_set_resource_kind,
            "resource_path" => write_set_resource_path,
            "base_blob_oid" => "b" * 40,
            "fencing_token" => 1
          }
        ]
      end
      write_set_reserved_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "WriteSetReserved",
          "stream_context" => "DevelopmentExecution",
          "stream_name" => "Attempt",
          "stream_id" => attempt_id,
          "stream_revision" => 2
        }
      end
      write_set_reserved_at_domain { Time.utc(2026, 8, 30, 12, 2) }
      write_set_expires_at_domain { Time.utc(2026, 8, 30, 12, 12) }
    end

    trait :released_write_set do
      with_write_set
      write_set_release_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "WriteSetReleased",
          "stream_context" => "DevelopmentExecution",
          "stream_name" => "Attempt",
          "stream_id" => attempt_id,
          "stream_revision" => 3
        }
      end
      write_set_released_at_domain { Time.utc(2026, 8, 30, 12, 5) }
    end

    trait :expanded_and_renewed_write_set do
      with_write_set

      transient do
        expanded_resource_id { SecureRandom.uuid_v7 }
        expanded_resource_kind { "file" }
        expanded_resource_path { "app/models/factory_expanded.rb" }
        expanded_lease_id { SecureRandom.uuid_v7 }
      end

      write_set_resources do
        [
          {
            "lease_id" => write_set_lease_id,
            "resource_id" => write_set_resource_id,
            "resource_kind" => write_set_resource_kind,
            "resource_path" => write_set_resource_path,
            "base_blob_oid" => "b" * 40,
            "fencing_token" => 1
          },
          {
            "lease_id" => expanded_lease_id,
            "resource_id" => expanded_resource_id,
            "resource_kind" => expanded_resource_kind,
            "resource_path" => expanded_resource_path,
            "base_blob_oid" => nil,
            "fencing_token" => 1
          }
        ]
      end
      write_set_last_expanded_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "WriteSetExpanded",
          "stream_context" => "DevelopmentExecution",
          "stream_name" => "Attempt",
          "stream_id" => attempt_id,
          "stream_revision" => 3
        }
      end
      write_set_last_expanded_at_domain { Time.utc(2026, 8, 30, 12, 4) }
      write_set_last_renewed_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "WriteSetRenewed",
          "stream_context" => "DevelopmentExecution",
          "stream_name" => "Attempt",
          "stream_id" => attempt_id,
          "stream_revision" => 4
        }
      end
      write_set_last_renewed_at_domain { Time.utc(2026, 8, 30, 12, 6) }
      write_set_previous_expires_at_domain { Time.utc(2026, 8, 30, 12, 12) }
      write_set_expires_at_domain { Time.utc(2099, 8, 30, 13) }
    end

    trait :completed_write_set_lifecycle do
      expanded_and_renewed_write_set
      write_set_release_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "WriteSetReleased",
          "stream_context" => "DevelopmentExecution",
          "stream_name" => "Attempt",
          "stream_id" => attempt_id,
          "stream_revision" => 5
        }
      end
      write_set_released_at_domain { Time.utc(2026, 8, 30, 12, 8) }
    end
  end
end
