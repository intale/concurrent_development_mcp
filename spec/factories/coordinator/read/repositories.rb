# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_repository, class: "Coordinator::Read::Repository" do
    transient do
      sequence(:repository_key) { "repository-#{_1}" }
    end

    repository_id { SecureRandom.uuid_v7 }
    scope { "project:factory" }
    display_name { repository_key.titleize }
    paths { [ "/work/#{repository_key}" ] }
    remotes { [] }
    registered_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "RepositoryRegistered",
        "stream_context" => "DevelopmentPlanning",
        "stream_name" => "Repository",
        "stream_id" => repository_id,
        "stream_revision" => 0
      }
    end
    registered_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    registered_markers do
      marker = Coordinator::Shared::CompoundMarkerBuilder.new.call(
        Coordinator::Shared::CompoundMarkerDefinitionV1.new(
          purpose: "scoped-repository-key",
          components: [ "scope:#{scope}", "repository-key:#{repository_key}" ]
        )
      ).marker
      [ marker ]
    end
    registered_metadata { { "schema_version" => 2 } }
    sequence(:registered_global_position, 200)
    registered_at_domain { Time.utc(2026, 8, 30, 12) }
    registered_at_store { registered_at_domain }
  end
end
