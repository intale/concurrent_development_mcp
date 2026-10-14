# frozen_string_literal: true

module Coordinator::Write::Operations
  class ExecuteCountCandidateCheckpoint
    include Dry::Monads[:result]

    def initialize(event_store:, loader: Coordinator::Write::ProjectionStatistics::CheckpointsLoader.new(event_store:),
      decider: Coordinator::Write::Domain::ProjectionStatistics::CountCheckpoint.new,
      writer: Coordinator::Write::ProjectionStatistics::CheckpointWriter.new(event_store:),
      id_generator: Coordinator::Write::IdGenerator.new, revision_retry: OptimisticRevisionRetry.new)
      @loader, @decider, @writer, @id_generator, @revision_retry = loader, decider, writer, id_generator, revision_retry
    end

    def call_command(command, caused_by: nil)
      event_ids = Array.new(2) { @id_generator.uuid_v7 }
      correlation_id = caused_by&.correlation_id || @id_generator.uuid_v7
      @revision_retry.call do
        state = @loader.state(command.statistics_id)
        unless state.initialized?
          next failure(command, :projection_statistics_not_found, "Checkpoint statistics have not been assigned")
        end
        scope = @loader.source_scope(command.source_event)
        unless scope
          next failure(command, :projection_statistics_source_mismatch, "Candidate's immutable ownership does not match its source")
        end
        decision = @decider.call(command:, state:, scope:,
          already_counted: @loader.counted?(command.statistics_id, scope.candidate_id))
        next decision if decision.failure?
        next Success(nil) unless decision.value!

        Success(@writer.call(plan: decision.value!, command_id: command.command_id, actor: command.actor,
          change_set_id: state.change_set_id, repository_id: state.repository_id,
          event_ids:, caused_by:, correlation_id:, expected_revision: state.latest_revision))
      end
    rescue PgEventstore::WrongExpectedRevisionError
      failure(command, :concurrency_conflict, "Statistics changed during all three attempts; this request may succeed if retried")
    rescue Coordinator::Write::EventHistoryLimitExceeded
      failure(command, :projection_statistics_history_limit, "Checkpoint ownership exceeds its immutable decision boundary")
    end

    private

    def failure(command, code, message)
      Failure(Coordinator::Write::OutcomeError.new(code:, message:,
        details: { statistics_id: command.statistics_id, source_event_id: command.source_event.event_id }))
    end
  end
end
