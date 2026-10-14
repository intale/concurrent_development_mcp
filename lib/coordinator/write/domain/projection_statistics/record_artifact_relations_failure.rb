# frozen_string_literal: true

module Coordinator::Write
  module Domain::ProjectionStatistics
    class RecordArtifactRelationsFailure
      include Dry::Monads[:result]

      def call(command:, state:, already_reconciled:, failure_recorded:)
        return Success(nil) if already_reconciled || failure_recorded

        unless state.initialized?
          return Failure(OutcomeError.new(code: :projection_statistics_not_found,
            message: "Artifact relation statistics have not been assigned", details: { statistics_id: command.statistics_id }))
        end
        event = Events::ProjectionNumbers::DevelopmentArtifactRelationsReconciliationFailedV1.new(
          statistics_id: command.statistics_id, source_event_id: command.source_event.event_id, failure: command.failure)
        stream = StreamFactory.new.development_artifact_relation_statistics(command.statistics_id)
        Success(Coordinator::Write::Domain::EventPlan.new(writes: [
          Coordinator::Write::Domain::EventWrite.new(stream:, event:)
        ]))
      end
    end
  end
end
