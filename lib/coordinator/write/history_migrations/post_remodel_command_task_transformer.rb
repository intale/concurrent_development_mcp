# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelCommandTaskTransformer
      include Dry::Monads[:result]

      COMMAND_TERMINALS = [
        Events::CommandRejectedV1,
        Events::CommandRejectedV2,
        Events::CommandSucceededV1
      ].freeze

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        source_event_plan_resolver:,
        command_input_rebinder:,
        request_marker: CommandLifecycle::RequestMarker.new,
        execution_lane: Tasks::ExecutionLane.new,
        tool_name_mapper: PostRemodelToolNameMapper.new,
        marker_codec: Coordinator::Shared::Markers::CodecV2.new,
        schema_registry: SourceEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @source_event_plan_resolver = source_event_plan_resolver
        @command_input_rebinder = command_input_rebinder
        @request_marker = request_marker
        @execution_lane = execution_lane
        @tool_name_mapper = tool_name_mapper
        @marker_codec = marker_codec
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        case source_payload
        when Events::CommandRegisteredV1
          command_registered(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when *COMMAND_TERMINALS
          command_terminal(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when PostRemodelEvents::CoordinationTaskSubmittedV3
          task_submitted(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::CoordinationTaskExecutionStartedV2, Events::CoordinationTaskCompletedV3
          task_lifecycle(
            migration_id:,
            source_config_name:,
            source_event:,
            source: source_payload
          )
        when Events::ProcessStepPlannedV1
          process_step(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        end
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error,
             EventHistoryLimitExceeded => error
        Failure(invalid(source_event, error.message))
      end

      private

      def command_registered(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        command = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_name: "Command",
          identity_role: "command"
        )
        return command if command.failure?

        task = task_for_command(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_command_id: source.command_id
        )
        return task if task.failure?

        command_id = command.value!.target_stream.stream_id
        task_id = task.value!&.target_stream&.stream_id
        actor = actor_from(source_event)
        markers = [
          "command:#{command_id}",
          ("task:#{task_id}" if task_id),
          @request_marker.call(actor:, request_id: source.request_id)
        ].compact
        Success([
          fact(
            target_stream: command.value!.target_stream,
            event: Events::CommandRegisteredV1.new(
              command_id:,
              request_id: source.request_id,
              tool_name: @tool_name_mapper.call(source.tool_name)
            ),
            markers:,
            step_name: "register-command",
            source_event:,
            metadata_extension: metadata(
              source_event,
              canonical_input_digest: source_event.metadata["canonical_input_digest"]
            )
          )
        ])
      end

      def command_terminal(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        command = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_name: "Command",
          identity_role: "command"
        )
        return command if command.failure?

        registration = source_registration(source_event, source_upper_position:)
        command_id = command.value!.target_stream.stream_id
        target = case source
        when Events::CommandSucceededV1
          Events::CommandSucceededV1.new(command_id:)
        when Events::CommandRejectedV1
          return Failure(invalid(source_event, "CommandRejected@1 lacks typed rejection details; cannot emit a current terminal fact"))
        when Events::CommandRejectedV2
          Events::CommandRejectedV2.new(
            command_id:,
            error: source.error,
            retryable: source.retryable
          )
        end
        Success([
          fact(
            target_stream: command.value!.target_stream,
            event: target,
            markers: [
              "command:#{command_id}",
              "tool:#{@tool_name_mapper.call(registration.tool_name)}"
            ],
            step_name: source.is_a?(Events::CommandSucceededV1) ? "succeed-command" : "reject-command",
            source_event:,
            metadata_extension: metadata(source_event)
          )
        ])
      end

      def task_submitted(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        task = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_name: "CoordinationTask",
          identity_role: "coordination-task"
        )
        return task if task.failure?

        command = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "CoordinatorControl",
          source_name: "Command",
          source_id: source.command_id,
          target_name: "Command",
          identity_role: "command"
        )
        return command if command.failure?

        command_id = command.value!.target_stream.stream_id
        migrated_input = @command_input_rebinder.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          document: source.command_input,
          command_id:
        )
        return migrated_input if migrated_input.failure?

        registration = source_registration(
          source_event,
          source_upper_position:,
          source_command_id: source.command_id
        )
        actor = Commands::Actor.new(
          kind: migrated_input.value!.document.input.actor.actor_kind,
          id: migrated_input.value!.document.input.actor.actor_id
        )
        task_id = task.value!.target_stream.stream_id
        tool_name = @tool_name_mapper.call(source.tool_name)
        request_marker = @request_marker.call(actor:, request_id: registration.request_id)
        Success([
          fact(
            target_stream: task.value!.target_stream,
            event: Events::CoordinationTaskSubmittedV3.new(
              task_id:,
              command_id:,
              tool_name:,
              command_input: migrated_input.value!.document,
              poll_interval_ms: source.poll_interval_ms,
              ttl_ms: source.ttl_ms
            ),
            markers: [
              "task:#{task_id}",
              "command:#{command_id}",
              request_marker,
              @execution_lane.marker(task_id),
              "tool:#{tool_name}"
            ],
            step_name: "submit-coordination-task",
            source_event:,
            metadata_extension: metadata(
              source_event,
              canonical_input_digest: migrated_input.value!.canonical_input_digest
            )
          )
        ])
      end

      def task_lifecycle(migration_id:, source_config_name:, source_event:, source:)
        task = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_name: "CoordinationTask",
          identity_role: "coordination-task"
        )
        return task if task.failure?

        task_id = task.value!.target_stream.stream_id
        target, step_name = if source.is_a?(Events::CoordinationTaskExecutionStartedV2)
          [ Events::CoordinationTaskExecutionStartedV2.new(task_id:), "start-coordination-task" ]
        else
          [ Events::CoordinationTaskCompletedV3.new(task_id:), "complete-coordination-task" ]
        end
        Success([
          fact(
            target_stream: task.value!.target_stream,
            event: target,
            markers: [ "task:#{task_id}" ],
            step_name:,
            source_event:,
            metadata_extension: metadata(source_event)
          )
        ])
      end

      def process_step(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        process_step = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_name: "ProcessStep",
          identity_role: "process-step"
        )
        return process_step if process_step.failure?

        parent = @source_event_plan_resolver.call(
          migration_id:,
          source_event:,
          source_event_id: source.source_event_id
        )
        return parent if parent.failure?

        target_command = process_step_command(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_command_id: source.target_command_id
        )
        return target_command if target_command.failure?

        target_entity_id = process_step_target_entity(
          migration_id:,
          source_config_name:,
          source_event:,
          source_target_entity_id: source.target_entity_id
        )
        return target_entity_id if target_entity_id.failure?

        subject_id = process_step_subject(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source:,
          target_parent: parent.value!
        )
        return subject_id if subject_id.failure?

        target_stream = process_step.value!.target_stream
        event = Events::ProcessStepPlannedV1.new(
          process_step_id: target_stream.stream_id,
          process_name: source.process_name,
          step_name: source.step_name,
          source_event_id: parent.value!.event_id,
          subject_kind: migrated_subject_kind(source.subject_kind),
          subject_id: subject_id.value!,
          target_command_id: target_command.value!,
          target_entity_id: target_entity_id.value!
        )
        encoded = @marker_codec.call(
          purpose: ProcessSteps::Planner::MARKER_PURPOSE,
          components: [
            { dimension: "process-name", value: event.process_name },
            { dimension: "source-event-id", value: event.source_event_id },
            { dimension: "step-name", value: event.step_name },
            { dimension: "subject-kind", value: event.subject_kind },
            { dimension: "subject-id", value: event.subject_id }
          ]
        )
        return Failure(encoded.failure) if encoded.failure?

        Success([
          fact(
            target_stream:,
            event:,
            markers: [ encoded.value!.marker ],
            step_name: "migrate-process-step",
            source_event:,
            metadata_extension: metadata(
              source_event,
              rule_version: source_event.metadata["rule_version"]
            )
          )
        ])
      end

      def process_step_command(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_command_id:
      )
        source_stream = StreamReference.new(
          context: "CoordinatorControl",
          stream_name: "Command",
          stream_id: source_command_id
        )
        if @event_store.read_at(source_stream, 0)&.global_position&.<=(source_upper_position)
          return resolve_entity(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_context: source_stream.context,
            source_name: source_stream.stream_name,
            source_id: source_stream.stream_id,
            target_name: "Command",
            identity_role: "command"
          ).fmap { _1.target_stream.stream_id }
        end

        allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_name: "Command",
          identity_role: "process-step-target-command"
        ).fmap { _1.target_stream.stream_id }
      end

      def process_step_target_entity(
        migration_id:,
        source_config_name:,
        source_event:,
        source_target_entity_id:
      )
        return Success(nil) unless source_target_entity_id

        allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_name: "ProcessStepTargetEntity",
          identity_role: "process-step-target-entity"
        ).fmap { _1.target_stream.stream_id }
      end

      def process_step_subject(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_parent:
      )
        case source.subject_kind
        when "boundary-index"
          Success(source.subject_id)
        when "resource-lease", "resource-work-intention"
          Success(target_parent.stream_id)
        when "change-set"
          resolve_entity(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_context: "DevelopmentPlanning",
            source_name: "ChangeSet",
            source_id: source.subject_id,
            target_name: "ChangeSet",
            identity_role: "change-set"
          ).fmap { _1.target_stream.stream_id }
        when "work-item-dependency"
          Success(migrated_dependency_id(source.subject_id, source_upper_position:))
        else
          Failure(invalid(source_event, "unsupported ProcessStep subject #{source.subject_kind.inspect}"))
        end
      end

      def migrated_subject_kind(source_kind)
        return "resource-work-intention" if source_kind == "resource-lease"

        source_kind
      end

      def migrated_dependency_id(source_dependency_id, source_upper_position:)
        event = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentExecution",
            stream_name: "WorkItem",
            event_types: [ "WorkItemDependencyDeclared" ],
            markers: [ "dependency:#{source_dependency_id}" ],
            maximum_count: 1,
            direction: :asc,
            to_position: source_upper_position
          )
        ).first
        event ? event.id : source_dependency_id
      end

      def task_for_command(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_command_id:
      )
        task_event = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "CoordinatorControl",
            stream_name: "CoordinationTask",
            event_types: [ "CoordinationTaskSubmitted" ],
            markers: [ "command:#{source_command_id}" ],
            maximum_count: 1,
            direction: :asc,
            to_position: source_upper_position
          )
        ).first
        return Success(nil) unless task_event

        allocate(
          migration_id:,
          source_config_name:,
          source_event: task_event,
          target_stream_name: "CoordinationTask",
          identity_role: "coordination-task"
        )
      end

      def source_registration(source_event, source_upper_position:, source_command_id: nil)
        stream_id = source_command_id || source_event.stream.stream_id
        event = @event_store.read_at(
          StreamReference.new(
            context: "CoordinatorControl",
            stream_name: "Command",
            stream_id:
          ),
          0
        )
        payload = event && load(event)
        valid = event && event.global_position <= source_upper_position &&
                payload.is_a?(Events::CommandRegisteredV1) && payload.command_id == stream_id
        raise ArgumentError, "source Command registration is absent or inconsistent" unless valid

        payload
      end

      def allocate(migration_id:, source_config_name:, source_event:, target_stream_name:, identity_role:)
        @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "CoordinatorControl",
          target_stream_name:,
          identity_role:
        )
      end

      def resolve_entity(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_context:,
        source_name:,
        source_id:,
        target_name:,
        identity_role:
      )
        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: source_context,
            stream_name: source_name,
            stream_id: source_id
          ),
          target_stream_context: source_context,
          target_stream_name: target_name,
          identity_role:
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def actor_from(source_event)
        Commands::Actor.new(
          kind: source_event.metadata.fetch("actor_kind"),
          id: source_event.metadata.fetch("actor_id")
        )
      end

      def metadata(source_event, **attributes)
        MigrationMetadataExtensionV1.new(
          attributed_actor: actor_from(source_event),
          policy_version: source_event.metadata["policy_version"],
          **attributes
        )
      end

      def fact(target_stream:, event:, markers:, step_name:, source_event:, metadata_extension:)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension:
        )
      end

      def invalid(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Post-remodel Command/Task transformation is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
