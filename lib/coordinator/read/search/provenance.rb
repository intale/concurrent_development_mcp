# frozen_string_literal: true

module Coordinator::Read::Search
  class Provenance < Coordinator::Read::Value
    attribute :source_table, Coordinator::Read::Types::String.enum(
      "skills", "skill_revisions", "skill_assets", "resources", "user_utterances", "agent_choices",
      "decision_definitions", "coordinator_contexts", "development_artifacts", "development_artifact_observations"
    )
    attribute :source_id, Coordinator::Read::Types::String
    attribute? :observation_id, Coordinator::Read::Types::DevelopmentArtifactObservationId
    attribute? :source_kind, Coordinator::Read::Types::String
    attribute? :source_locator, Coordinator::Read::Types::String
    attribute? :source_revision, Coordinator::Read::Types::String
  end
end
