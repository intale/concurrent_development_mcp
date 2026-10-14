# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRecordDevelopmentArtifactRelationsReconciliationFailure
      include Dry::Monads[:result]

      def initialize(event_store:, loader: ProjectionStatistics::ArtifactRelationsLoader.new(event_store:),
        decider: Domain::ProjectionStatistics::RecordArtifactRelationsFailure.new,
        writer: ProjectionStatistics::ArtifactRelationWriter.new(event_store:),
        id_generator: IdGenerator.new, revision_retry: OptimisticRevisionRetry.new)
        @loader, @decider, @writer = loader, decider, writer
        @id_generator, @revision_retry = id_generator, revision_retry
      end

      def call_command(command, caused_by: nil)
        event_ids = [ @id_generator.uuid_v7 ]
        correlation_id = caused_by&.correlation_id || @id_generator.uuid_v7
        @revision_retry.call do
          state = @loader.state(command.statistics_id)
          unless state.initialized?
            next failure(command, :projection_statistics_not_found, "Artifact relation statistics have not been assigned")
          end
          unless @loader.source(command.source_event, artifact_id: state.artifact_id)
            next failure(command, :projection_statistics_source_mismatch, "Relation source does not match the assigned Artifact")
          end
          decision = @decider.call(command:, state:,
            already_reconciled: @loader.reconciled?(command.statistics_id, command.source_event.event_id),
            failure_recorded: @loader.failure_recorded?(command.statistics_id, command.command_id))
          next decision if decision.failure? || !decision.value!

          Success(@writer.call(plan: decision.value!, command_id: command.command_id, actor: command.actor,
            artifact_id: state.artifact_id, event_ids:, source_event_id: command.source_event.event_id,
            caused_by:, correlation_id:, expected_revision: state.latest_revision))
        end
      rescue PgEventstore::WrongExpectedRevisionError
        failure(command, :concurrency_conflict, "Statistics failure evidence raced during all three attempts; retry may succeed")
      end

      private

      def failure(command, code, message)
        Failure(OutcomeError.new(code:, message:,
          details: { statistics_id: command.statistics_id, source_event_id: command.source_event.event_id }))
      end
    end
  end
end
