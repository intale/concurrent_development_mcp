# frozen_string_literal: true

module Coordinator::Write
  module Domain::ProjectionStatistics
    class EnsureArtifactRelations
      include Dry::Monads[:result]

      def call(command:, artifact_exists:)
        unless artifact_exists
          return Failure(OutcomeError.new(code: :development_artifact_not_found,
            message: "Source Development Artifact was not found", details: { artifact_id: command.artifact_id }))
        end
        stream = StreamFactory.new.development_artifact_relation_statistics(command.statistics_id)
        events = [
          Events::ProjectionNumbers::DevelopmentArtifactRelationStatisticsAssignedV1.new(
            statistics_id: command.statistics_id, artifact_id: command.artifact_id),
          Events::ProjectionNumbers::DevelopmentArtifactRelationsNumberChangedV1.new(
            artifact_id: command.artifact_id, active_relations_number: 0, lifetime_relations_number: 0)
        ]
        Success(Coordinator::Write::Domain::EventPlan.new(writes: events.map do
          Coordinator::Write::Domain::EventWrite.new(stream:, event: _1)
        end))
      end
    end
  end
end
