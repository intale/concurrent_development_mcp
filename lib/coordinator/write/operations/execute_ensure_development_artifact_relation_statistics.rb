# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteEnsureDevelopmentArtifactRelationStatistics
      include Dry::Monads[:result]

      def initialize(event_store:, registry: NaturalKeys::Registry.new(event_store:),
        loader: ProjectionStatistics::ArtifactRelationsLoader.new(event_store:),
        artifact_loader: DevelopmentArtifacts::Loader.new(event_store:),
        decider: Domain::ProjectionStatistics::EnsureArtifactRelations.new,
        writer: ProjectionStatistics::ArtifactRelationWriter.new(event_store:),
        id_generator: IdGenerator.new, stream_factory: StreamFactory.new)
        @event_store, @registry, @loader, @artifact_loader = event_store, registry, loader, artifact_loader
        @decider, @writer, @id_generator, @stream_factory = decider, writer, id_generator, stream_factory
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

          stream = @stream_factory.development_artifact_relation_statistics(command.statistics_id)
          if @event_store.read_at(stream, 0)
            next Failure(OutcomeError.new(code: :projection_statistics_identity_reused,
              message: "Proposed statistics UUID is already assigned", details: { statistics_id: command.statistics_id }))
          end
          decision = @decider.call(command:, artifact_exists: @artifact_loader.captured?(command.artifact_id))
          next decision if decision.failure?

          @writer.call(plan: decision.value!, command_id: command.command_id, actor: command.actor,
            artifact_id: command.artifact_id, event_ids:, caused_by:, correlation_id:)
          Success(command.statistics_id)
        end
      end

      private

      def find(command)
        result = @registry.find(selector: @loader.selector(command.artifact_id),
          identity_from: ->(event) { event.data.fetch("statistics_id") })
        return result if result.success?

        Failure(OutcomeError.new(code: :projection_statistics_registry_invalid,
          message: result.failure.message,
          details: { artifact_id: command.artifact_id, statistics_id: command.statistics_id }))
      end
    end
  end
end
