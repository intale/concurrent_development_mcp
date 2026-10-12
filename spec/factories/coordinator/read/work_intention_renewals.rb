# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_work_intention_renewal, class: "Coordinator::Read::WorkIntentionRenewal" do
    renewal_id { SecureRandom.uuid_v7 }
    task_id { SecureRandom.uuid_v7 }
    intention_set_id { SecureRandom.uuid_v7 }
    attempt_id { "factory-renewal-attempt" }
    actor_kind { "agent" }
    actor_id { "factory-agent" }
    status { "requested" }
    expires_at { Time.now.utc + 900 }
    correlation_id { SecureRandom.uuid_v7 }
    request_event do
      { "event_id" => SecureRandom.uuid_v7, "type" => "WorkIntentionSetRenewalRequested",
        "stream_context" => "DevelopmentCoordination", "stream_name" => "WorkIntentionSetRenewal",
        "stream_id" => renewal_id, "stream_revision" => 0 }
    end
    members do
      [ { "position" => 0, "intention_id" => SecureRandom.uuid_v7, "resource_id" => SecureRandom.uuid_v7,
        "fencing_token" => 1, "status" => "pending", "renewal_event" => nil, "failure" => nil } ]
    end
  end
end
