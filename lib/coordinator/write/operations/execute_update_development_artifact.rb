# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteUpdateDevelopmentArtifact < Dry::Operation
      TOOL_NAME = "development_artifact_update"

      def initialize(
        event_store:,
        preparer: PrepareUpdateDevelopmentArtifact.new,
        loader: DevelopmentArtifacts::Loader.new(event_store:),
        decider: Domain::DevelopmentArtifacts::Update.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        marker_builder: DevelopmentArtifacts::MarkerBuilder.new,
        completion_builder: CommandResultBuilder.new
      )
        @event_store = event_store
        @preparer = preparer
        @loader = loader
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
        @marker_builder = marker_builder
        @completion_builder = completion_builder
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        preparation = prepare_logical_values(command)
        state, current_revision = @loader.load_with_revision(command.artifact_id)
        preview = decide(command:, state:, current_revision:)
        return preview if preview.failure?

        if preview.value!.event_plan && preview.value!.event_plan.writes.length > 1
          @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        else
          execute_decision(
            preview.value!, command:, preparation:, caused_by:, expected_revision: command.expected_revision
          )
        end
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(
          OutcomeError.new(
            code: :development_artifact_revision_conflict,
            message: "Development Artifact revision changed; retrieve the current artifact and retry",
            details: {
              artifact_id: command.artifact_id,
              expected_revision: command.expected_revision,
              current_revision: @loader.load_with_revision(command.artifact_id).last
            }
          )
        )
      end

      private

      def prepare_logical_values(command)
        DevelopmentArtifactUpdatePreparationV1.new(
          recorded_at: @clock.now,
          input_digest: @input_digest.development_artifact_update(command),
          event_ids: (Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT * 2 + 5).times.map { @id_generator.uuid_v7 }
        )
      end

      def decide(command:, state:, current_revision:)
        return @decider.call(artifact_id: command.artifact_id, changes: command.changes, state:) unless
          state.created
        return revision_conflict(command, current_revision) unless current_revision == command.expected_revision

        @decider.call(artifact_id: command.artifact_id, changes: command.changes, state:)
      end

      def execute_attempt(command:, preparation:, caused_by:, expected_revision: nil)
        state, current_revision = @loader.load_with_revision(command.artifact_id)
        decision_result = decide(command:, state:, current_revision:)
        return decision_result if decision_result.failure?
        execute_decision(
          decision_result.value!, command:, preparation:, caused_by:, expected_revision:
        )
      end

      def execute_decision(decision, command:, preparation:, caused_by:, expected_revision: nil)
        persisted = persist_domain_plan(
          decision.event_plan,
          command:,
          preparation:,
          caused_by:,
          expected_revision:
        )
        event = persisted.last
        Success(
          @completion_builder.development_artifact_update(
            command:, decision:, input_digest: preparation.input_digest,
            persisted_events: persisted,
            completed_at: event&.created_at&.utc&.iso8601(6) || preparation.recorded_at
          )
        )
      end

      def revision_conflict(command, current_revision)
        Failure(
          OutcomeError.new(
            code: :development_artifact_revision_conflict,
            message: "Development Artifact revision changed; retrieve the current artifact and retry",
            details: { artifact_id: command.artifact_id, expected_revision: command.expected_revision, current_revision: }
          )
        )
      end

      def persist_domain_plan(plan, command:, preparation:, caused_by:, expected_revision: nil)
        return [] unless plan

        events = plan.writes.each_with_index.map do |write, index|
          @event_factory.build!(
            event: write.event,
            event_id: preparation.event_ids.fetch(index),
            metadata: event_metadata(write.event, command),
            markers: @marker_builder.artifact(event: write.event, command_id: command.command_id),
            caused_by:
          )
        end
        @event_store.append(
          plan.writes.first.stream,
          events,
          expected_revision:
        )
      end

      def event_metadata(event, command)
        attributes = {
          command_id: command.command_id, actor_kind: command.actor.kind, actor_id: command.actor.id,
          recorded_by: "coordinator", policy_version: "development-artifact-repository/v2"
        }
        case event
        when Events::DevelopmentArtifactContentChangedV1
          content = command.changes.content
          Metadata::ContentV1.new(**attributes, encoding: content.encoding, media_type: content.media_type,
                                  byte_size: content.byte_size, content_sha256: content.content_sha256)
        when Events::DevelopmentArtifactSourceChangedV1
          Metadata::CollectorV1.new(**attributes, collector: command.changes.source.collector)
        else
          EventMetadata.new(**attributes)
        end
      end
    end
  end
end
