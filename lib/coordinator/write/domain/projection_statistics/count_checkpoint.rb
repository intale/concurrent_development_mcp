# frozen_string_literal: true

module Coordinator::Write::Domain::ProjectionStatistics
  class CountCheckpoint
    include Dry::Monads[:result]

    def call(command:, state:, scope:, already_counted:)
      unless state.initialized?
        return Failure(Coordinator::Write::OutcomeError.new(code: :projection_statistics_not_found,
          message: "Checkpoint statistics have not been assigned", details: { statistics_id: command.statistics_id }))
      end
      unless state.change_set_id == scope.change_set_id && state.repository_id == scope.repository_id
        return Failure(Coordinator::Write::OutcomeError.new(code: :projection_statistics_source_mismatch,
          message: "Candidate does not belong to the assigned ChangeSet and Repository",
          details: { statistics_id: command.statistics_id, candidate_id: scope.candidate_id }))
      end
      return Success(nil) if already_counted

      stream = Coordinator::Write::StreamFactory.new.checkpoint_statistics(command.statistics_id)
      events = [
        Coordinator::Write::Events::ProjectionNumbers::ChangeSetRepositoryCheckpointNumberChangedV1.new(
          change_set_id: state.change_set_id, repository_id: state.repository_id,
          checkpoints_number: state.checkpoints_number + 1),
        Coordinator::Write::Events::ProjectionNumbers::CandidateCheckpointCountedV1.new(
          statistics_id: command.statistics_id, candidate_id: scope.candidate_id)
      ]
      Success(Coordinator::Write::Domain::EventPlan.new(writes: events.map do
        Coordinator::Write::Domain::EventWrite.new(stream:, event: _1)
      end))
    end
  end
end
