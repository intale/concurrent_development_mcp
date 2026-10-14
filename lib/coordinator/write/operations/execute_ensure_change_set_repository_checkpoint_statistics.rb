# frozen_string_literal: true

module Coordinator::Write::Operations
  class ExecuteEnsureChangeSetRepositoryCheckpointStatistics
    include Dry::Monads[:result]

    def initialize(event_store:, registry: Coordinator::Write::NaturalKeys::Registry.new(event_store:),
      loader: Coordinator::Write::ProjectionStatistics::CheckpointsLoader.new(event_store:),
      decider: Coordinator::Write::Domain::ProjectionStatistics::EnsureCheckpoints.new,
      writer: Coordinator::Write::ProjectionStatistics::CheckpointWriter.new(event_store:),
      id_generator: Coordinator::Write::IdGenerator.new, stream_factory: Coordinator::Write::StreamFactory.new)
      @event_store, @registry, @loader, @decider = event_store, registry, loader, decider
      @writer, @id_generator, @stream_factory = writer, id_generator, stream_factory
    end

    def call_command(command, caused_by: nil)
      existing = find(command)
      return existing if existing.failure?
      return Success(existing.value!.identity) if existing.value!

      event_ids = Array.new(2) { @id_generator.uuid_v7 }
      correlation_id = caused_by&.correlation_id || @id_generator.uuid_v7
      @event_store.multiple do
        found = find(command)
        next found if found.failure?
        next Success(found.value!.identity) if found.value!

        stream = @stream_factory.checkpoint_statistics(command.statistics_id)
        if @event_store.read_at(stream, 0)
          next Failure(Coordinator::Write::OutcomeError.new(code: :projection_statistics_identity_reused,
            message: "Proposed statistics UUID is already assigned", details: { statistics_id: command.statistics_id }))
        end
        decision = @decider.call(command:,
          change_set_exists: @loader.owner_exists?(@stream_factory.change_set(command.change_set_id), "ChangeSetCreated"),
          repository_exists: @loader.owner_exists?(@stream_factory.repository(command.repository_id), "RepositoryRegistered"))
        next decision if decision.failure?

        @writer.call(plan: decision.value!, command_id: command.command_id, actor: command.actor,
          change_set_id: command.change_set_id, repository_id: command.repository_id,
          event_ids:, caused_by:, correlation_id:)
        Success(command.statistics_id)
      end
    end

    private

    def find(command)
      result = @registry.find(selector: @loader.selector(change_set_id: command.change_set_id, repository_id: command.repository_id),
        identity_from: ->(event) { event.data.fetch("statistics_id") })
      return result if result.success?

      Failure(Coordinator::Write::OutcomeError.new(code: :projection_statistics_registry_invalid,
        message: result.failure.message, details: { change_set_id: command.change_set_id, repository_id: command.repository_id }))
    end
  end
end
