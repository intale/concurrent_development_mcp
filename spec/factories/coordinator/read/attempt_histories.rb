# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_attempt_history, class: "Coordinator::Read::AttemptHistory" do
    sequence(:attempt_id) { "attempt-#{_1}" }
    sequence(:change_set_id) { "change-set-#{_1}" }
    sequence(:work_item_id) { "work-item-#{_1}" }
    sequence(:authorized_global_position, 1)
    agent_id { "factory-agent" }
    base_snapshots do
      [ { "repository_id" => SecureRandom.uuid_v7, "object_format" => "sha1", "commit_oid" => "a" * 40 } ]
    end
    status { "authorized" }
    projection_version { 7 }
    authorization_event do
      { "event_id" => SecureRandom.uuid_v7, "type" => "AttemptStarted",
        "stream_context" => "DevelopmentCoordination", "stream_name" => "Attempt",
        "stream_id" => attempt_id, "stream_revision" => 0 }
    end
    authorized_at_domain { Time.utc(2026, 8, 30, 12) }

    trait :with_work_intention_set do
      transient do
        work_intention_resource_id { SecureRandom.uuid_v7 }
        work_intention_resource_kind { "file" }
        work_intention_resource_path { "app/models/factory_intention.rb" }
        work_intention_id { SecureRandom.uuid_v7 }
        work_intention_mode { "shared" }
        work_intention_purpose { "Implement the assigned WorkItem" }
        work_intention_context { nil }
      end
      work_intention_set_id { SecureRandom.uuid_v7 }
      work_intention_set_repository_id { base_snapshots.sole.fetch("repository_id") }
      work_intention_set_policy_version { "coordinator-work-intention/v1" }
      work_intention_set_intentions do
        [ { "intention_id" => work_intention_id, "resource_id" => work_intention_resource_id,
           "resource_kind" => work_intention_resource_kind, "resource_path" => work_intention_resource_path,
           "base_blob_oid" => "b" * 40, "mode" => work_intention_mode,
           "purpose" => work_intention_purpose, "context" => work_intention_context, "fencing_token" => 1 } ]
      end
      work_intention_set_declared_event do
        { "event_id" => SecureRandom.uuid_v7, "type" => "WorkIntentionSetCreated",
          "stream_context" => "DevelopmentCoordination", "stream_name" => "WorkIntentionSet",
          "stream_id" => work_intention_set_id, "stream_revision" => 0 }
      end
      work_intention_set_declared_at_domain { Time.utc(2026, 8, 30, 12, 2) }
      work_intention_set_expires_at_domain { Time.utc(2026, 8, 30, 12, 12) }
    end

    trait :exclusive_work_intention_set do
      with_work_intention_set
      work_intention_mode { "exclusive" }
      work_intention_purpose { "Replace the complete resource after reviewing competing work" }
      work_intention_context { "The assigned rewrite requires exclusive coordination" }
    end

    trait :withdrawn_work_intention_set do
      with_work_intention_set
      work_intention_set_withdrawal_event do
        { "event_id" => SecureRandom.uuid_v7, "type" => "ResourceWorkIntentionWithdrawn",
          "stream_context" => "DevelopmentCoordination", "stream_name" => "ResourceWorkIntention",
          "stream_id" => work_intention_id, "stream_revision" => 1 }
      end
      work_intention_set_withdrawn_at_domain { Time.utc(2026, 8, 30, 12, 5) }
    end

    trait :expanded_and_renewed_work_intention_set do
      with_work_intention_set
      transient do
        expanded_resource_id { SecureRandom.uuid_v7 }
        expanded_resource_kind { "file" }
        expanded_resource_path { "app/models/factory_expanded.rb" }
        expanded_intention_id { SecureRandom.uuid_v7 }
      end
      work_intention_set_intentions do
        [ { "intention_id" => work_intention_id, "resource_id" => work_intention_resource_id,
           "resource_kind" => work_intention_resource_kind, "resource_path" => work_intention_resource_path,
           "base_blob_oid" => "b" * 40, "mode" => work_intention_mode,
           "purpose" => work_intention_purpose, "context" => work_intention_context, "fencing_token" => 1 },
         { "intention_id" => expanded_intention_id, "resource_id" => expanded_resource_id,
           "resource_kind" => expanded_resource_kind, "resource_path" => expanded_resource_path,
           "base_blob_oid" => nil, "mode" => work_intention_mode,
           "purpose" => "Extend assigned work to an additional resource",
           "context" => work_intention_context, "fencing_token" => 1 } ]
      end
      work_intention_set_last_expanded_event do
        { "event_id" => SecureRandom.uuid_v7, "type" => "ResourceWorkIntentionDeclared",
          "stream_context" => "DevelopmentCoordination", "stream_name" => "ResourceWorkIntention",
          "stream_id" => expanded_intention_id, "stream_revision" => 0 }
      end
      work_intention_set_last_expanded_at_domain { Time.utc(2026, 8, 30, 12, 4) }
      work_intention_set_last_renewed_event do
        { "event_id" => SecureRandom.uuid_v7, "type" => "ResourceWorkIntentionRenewed",
          "stream_context" => "DevelopmentCoordination", "stream_name" => "ResourceWorkIntention",
          "stream_id" => work_intention_id, "stream_revision" => 1 }
      end
      work_intention_set_last_renewed_at_domain { Time.utc(2026, 8, 30, 12, 6) }
      work_intention_set_previous_expires_at_domain { Time.utc(2026, 8, 30, 12, 12) }
      work_intention_set_expires_at_domain { Time.utc(2099, 8, 30, 13) }
    end

    trait :withdrawn_expanded_work_intention_set do
      expanded_and_renewed_work_intention_set
      work_intention_set_withdrawal_event do
        { "event_id" => SecureRandom.uuid_v7, "type" => "ResourceWorkIntentionWithdrawn",
          "stream_context" => "DevelopmentCoordination", "stream_name" => "ResourceWorkIntention",
          "stream_id" => expanded_intention_id, "stream_revision" => 1 }
      end
      work_intention_set_withdrawn_at_domain { Time.utc(2026, 8, 30, 12, 8) }
    end
  end
end
