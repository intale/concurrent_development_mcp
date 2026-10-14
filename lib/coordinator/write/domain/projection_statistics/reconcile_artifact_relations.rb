# frozen_string_literal: true

module Coordinator::Write
  module Domain::ProjectionStatistics
    class ReconcileArtifactRelations
      include Dry::Monads[:result]

      def call(command:, state:, relation_states:, already_reconciled:)
        return Success(nil) if already_reconciled

        unless state.initialized?
          return Failure(OutcomeError.new(code: :projection_statistics_not_found,
            message: "Artifact relation statistics have not been assigned", details: { statistics_id: command.statistics_id }))
        end
        active = relation_states.count(&:active?)
        lifetime = relation_states.count { !_1.declaration.nil? }
        events = []
        unless state.active_relations_number == active && state.lifetime_relations_number == lifetime
          events << Events::ProjectionNumbers::DevelopmentArtifactRelationsNumberChangedV1.new(
            artifact_id: state.artifact_id, active_relations_number: active, lifetime_relations_number: lifetime)
        end
        events << Events::ProjectionNumbers::DevelopmentArtifactRelationsReconciledV1.new(
          statistics_id: command.statistics_id, source_event_id: command.source_event.event_id)
        stream = StreamFactory.new.development_artifact_relation_statistics(command.statistics_id)
        Success(Coordinator::Write::Domain::EventPlan.new(writes: events.map do
          Coordinator::Write::Domain::EventWrite.new(stream:, event: _1)
        end))
      end
    end
  end
end
