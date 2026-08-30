# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_candidate_changed_resource,
          class: "Coordinator::Read::CandidateChangedResource" do
    sequence(:candidate_id) { "CAN-factory-changed-#{_1}" }
    sequence(:change_set_id) { "CS-factory-changed-#{_1}" }
    repository_id { SecureRandom.uuid_v7 }
    sequence(:path) { "lib/factory_changed_#{_1}.rb" }
  end

  factory :coordinator_read_candidate_observed_input,
          class: "Coordinator::Read::CandidateObservedInput" do
    sequence(:candidate_id) { "CAN-factory-input-#{_1}" }
    sequence(:change_set_id) { "CS-factory-input-#{_1}" }
    repository_id { SecureRandom.uuid_v7 }
    sequence(:path) { "lib/factory_input_#{_1}.rb" }
  end

  factory :coordinator_read_candidate_impact_key,
          class: "Coordinator::Read::CandidateImpactKey" do
    sequence(:candidate_id) { "CAN-factory-impact-#{_1}" }
    sequence(:change_set_id) { "CS-factory-impact-#{_1}" }
    direction { "produces" }
    sequence(:impact_key) { "contract:factory-#{_1}:v1" }
  end
end
