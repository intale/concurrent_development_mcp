# frozen_string_literal: true

module Coordinator::Write::Domain::ProjectionStatistics
  class EnsureCheckpoints
    include Dry::Monads[:result]

    def call(command:, change_set_exists:, repository_exists:)
      unless change_set_exists
        return Failure(Coordinator::Write::OutcomeError.new(code: :change_set_not_found,
          message: "Checkpoint ChangeSet was not found", details: { change_set_id: command.change_set_id }))
      end
      unless repository_exists
        return Failure(Coordinator::Write::OutcomeError.new(code: :repository_not_registered,
          message: "Checkpoint Repository was not registered", details: { repository_id: command.repository_id }))
      end
      stream = Coordinator::Write::StreamFactory.new.checkpoint_statistics(command.statistics_id)
      events = [
        Coordinator::Write::Events::ProjectionNumbers::ChangeSetRepositoryCheckpointStatisticsAssignedV1.new(
          statistics_id: command.statistics_id, change_set_id: command.change_set_id, repository_id: command.repository_id),
        Coordinator::Write::Events::ProjectionNumbers::ChangeSetRepositoryCheckpointNumberChangedV1.new(
          change_set_id: command.change_set_id, repository_id: command.repository_id, checkpoints_number: 0)
      ]
      Success(Coordinator::Write::Domain::EventPlan.new(writes: events.map do
        Coordinator::Write::Domain::EventWrite.new(stream:, event: _1)
      end))
    end
  end
end
