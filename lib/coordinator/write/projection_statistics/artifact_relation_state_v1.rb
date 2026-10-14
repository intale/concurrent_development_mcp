# frozen_string_literal: true

module Coordinator::Write::ProjectionStatistics
  class ArtifactRelationStateV1 < Coordinator::Write::Value
    attribute :statistics_id, Coordinator::Write::Types::UuidV7
    attribute :artifact_id, Coordinator::Write::Types::DevelopmentArtifactId.optional
    attribute :active_relations_number, Coordinator::Write::Types::Integer.optional
    attribute :lifetime_relations_number, Coordinator::Write::Types::Integer.optional
    attribute :latest_revision, Coordinator::Write::Types::Integer.constrained(gteq: -1)

    def initialized?
      !artifact_id.nil? && !active_relations_number.nil? && !lifetime_relations_number.nil?
    end
  end
end
