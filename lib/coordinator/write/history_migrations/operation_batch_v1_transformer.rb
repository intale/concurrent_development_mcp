# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class OperationBatchV1Transformer
      include Dry::Monads[:result]

      def initialize(
        context_resolver:,
        target_event_reference_resolver:,
        target_plan_builder:,
        request_marker: CommandLifecycle::RequestMarker.new,
        rejection_retryability: LegacyCommandRejectionRetryability.new,
        manifest_builder: OperationBatches::ManifestBuilder.new
      )
        @context_resolver = context_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @target_plan_builder = target_plan_builder
        @request_marker = request_marker
        @rejection_retryability = rejection_retryability
        @manifest_builder = manifest_builder
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        resolved = resolve_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_payload:
        )
        return resolved if resolved.failure?

        transformed = transform(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_payload,
          context: resolved.value!
        )
        transformed.failure? ? transformed : Success(Array(transformed.value!).freeze)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def resolve_context(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_payload:
      )
        common = { migration_id:, source_config_name:, source_upper_position:, source_event: }
        if source_payload.is_a?(LegacyEvents::OperationBatchCreatedV1)
          @context_resolver.from_creation(**common, source_creation: source_payload)
        else
          @context_resolver.from_stream(**common)
        end
      end

      def transform(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        context:
      )
        case source
        when LegacyEvents::OperationBatchCreatedV1
          Success(creation_facts(source_event:, source:, context:))
        when LegacyEvents::OperationBatchItemSucceededV1
          success_facts(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            context:
          )
        when LegacyEvents::OperationBatchItemRejectedV1
          rejection_facts(migration_id:, source_event:, source:, context:)
        when LegacyEvents::OperationBatchContinuationRequestedV1
          Success(
            batch_fact(
              context:,
              event: Events::OperationBatchContinuationRequestedV2.new(
                batch_id: context.batch_id,
                page_start: source.page_start,
                page_end: source.page_end
              ),
              markers: context.markers,
              step_name: "request-operation-batch-continuation",
              metadata_extension: actor_metadata(source_event)
            )
          )
        when LegacyEvents::OperationBatchCancellationRequestedV1
          Success(
            batch_fact(
              context:,
              event: Events::OperationBatchCancellationRequestedV2.new(batch_id: context.batch_id),
              markers: context.markers,
              step_name: "request-operation-batch-cancellation",
              metadata_extension: actor_metadata(source_event)
            )
          )
        when LegacyEvents::OperationBatchCancelledV1
          Success(
            batch_fact(
              context:,
              event: Events::OperationBatchCancelledV2.new(batch_id: context.batch_id),
              markers: context.markers,
              step_name: "cancel-operation-batch",
              metadata_extension: actor_metadata(source_event)
            )
          )
        when LegacyEvents::OperationBatchCompletedV1
          Success(
            batch_fact(
              context:,
              event: Events::OperationBatchCompletedV2.new(batch_id: context.batch_id),
              markers: context.markers,
              step_name: "complete-operation-batch",
              metadata_extension: actor_metadata(
                source_event,
                outcome_digest: source.outcome_manifest_digest
              )
            )
          )
        else
          Failure(inconsistent(source_event, "unsupported OperationBatch source contract"))
        end
      end

      def creation_facts(source_event:, source:, context:)
        actor = actor_metadata(
          source_event,
          manifest_digest: target_manifest_digest(context),
          page_size: source.page_size,
          encoded_byte_size: source.encoded_byte_size
        )
        facts = [
          batch_fact(
            context:,
            event: Events::OperationBatchCreatedV2.new(batch_id: context.batch_id),
            markers: context.markers,
            step_name: "create-operation-batch",
            metadata_extension: actor
          ),
          batch_fact(
            context:,
            event: Events::OperationBatchTargetSelectedV1.new(
              batch_id: context.batch_id,
              target_tool: source.target_tool
            ),
            markers: context.markers + [ "tool:#{source.target_tool}" ],
            step_name: "select-operation-batch-target",
            metadata_extension: actor_metadata(source_event)
          )
        ]
        context.items.each do |item|
          suffix = format("%04d", item.index)
          facts << batch_fact(
            context:,
            event: Events::OperationBatchItemEnqueuedV1.new(
              batch_id: context.batch_id,
              index: item.index,
              command_id: item.command_id,
              input: item.submitted_input
            ),
            markers: context.item_markers(item.index) + [
              "command:#{item.command_id}",
              "tool:#{source.target_tool}"
            ],
            step_name: "enqueue-operation-batch-item-#{suffix}",
            metadata_extension: actor_metadata(
              source_event,
              canonical_input_digest: item.canonical_input_digest,
              encoded_byte_size: item.encoded_byte_size
            )
          )
          facts << command_registration_fact(item, context:, step_suffix: suffix, source_event:)
        end
        facts.freeze
      end

      def command_registration_fact(item, context:, step_suffix:, source_event:)
        TransformedFactV1.new(
          target_stream: item.target_command_stream,
          event: Events::CommandRegisteredV1.new(
            command_id: item.command_id,
            request_id: item.request_id,
            tool_name: item.target_item.command_input.tool_name
          ),
          markers: context.item_markers(item.index) + [
            "command:#{item.command_id}",
            "tool:#{item.target_item.command_input.tool_name}",
            @request_marker.call(actor: item.actor, request_id: item.request_id)
          ],
          step_name: "register-operation-batch-command-#{step_suffix}",
          metadata_extension: MigrationMetadataExtensionV1.new(
            attributed_actor: item.actor,
            policy_version: source_event.metadata["policy_version"],
            canonical_input_digest: item.canonical_input_digest
          )
        )
      end

      def success_facts(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        context:
      )
        item = context.item(source.index)
        return Failure(inconsistent(source_event, "successful item is absent from the migrated manifest")) unless item

        completion = @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.target_completion,
          target_stream_context: "CoordinatorControl",
          target_stream_name: "Command",
          identity_role: "command",
          target_event_type: "CommandSucceeded",
          target_step_name: "succeed-command"
        )
        return completion if completion.failure?

        Success(
          outcome_facts(
            source_event:,
            context:,
            item:,
            outcome: Events::OperationBatchItemSucceededV2.new(
              batch_id: context.batch_id,
              index: item.index,
              command_id: item.command_id
            ),
            completion: completion.value!,
            outcome_step: "record-operation-batch-item-success",
            metadata_extension: actor_metadata(
              source_event,
              canonical_input_digest: source.canonical_input_digest
            )
          )
        )
      end

      def rejection_facts(migration_id:, source_event:, source:, context:)
        item = context.item(source.index)
        return Failure(inconsistent(source_event, "rejected item is absent from the migrated manifest")) unless item

        error = source.result.data
        retryable = @rejection_retryability.call(error.code)
        terminal = TransformedFactV1.new(
          target_stream: item.target_command_stream,
          event: Events::CommandRejectedV2.new(
            command_id: item.command_id,
            error:,
            retryable:
          ),
          markers: [
            "command:#{item.command_id}",
            "tool:#{item.target_item.command_input.tool_name}"
          ],
          step_name: "reject-command",
          metadata_extension: MigrationMetadataExtensionV1.new(
            attributed_actor: item.actor,
            policy_version: source_event.metadata["policy_version"]
          )
        )
        plans = @target_plan_builder.call(
          migration_id:,
          source_event:,
          transformed_facts: [ terminal ]
        )
        return plans if plans.failure?

        completion = plans.value!.sole.target_event
        outcome = Events::OperationBatchItemRejectedV2.new(
          batch_id: context.batch_id,
          index: item.index,
          command_id: item.command_id,
          code: error.code,
          reason: error.message,
          retryable:
        )
        Success(
          [
            terminal,
            *outcome_facts(
              source_event:,
              context:,
              item:,
              outcome:,
              completion:,
              outcome_step: "record-operation-batch-item-rejection",
              metadata_extension: actor_metadata(
                source_event,
                canonical_input_digest: source.canonical_input_digest
              )
            )
          ].freeze
        )
      end

      def outcome_facts(
        source_event:,
        context:,
        item:,
        outcome:,
        completion:,
        outcome_step:,
        metadata_extension:
      )
        [
          batch_fact(
            context:,
            event: outcome,
            markers: context.item_markers(item.index) + [ "command:#{item.command_id}" ],
            step_name: outcome_step,
            metadata_extension:
          ),
          batch_fact(
            context:,
            event: Events::OperationBatchItemCompletionLinkedV1.new(
              batch_id: context.batch_id,
              index: item.index,
              command_id: item.command_id,
              completion:
            ),
            markers: context.item_markers(item.index) + [
              "command:#{item.command_id}",
              "command-completion-event:#{completion.event_id}"
            ],
            step_name: "link-operation-batch-item-completion",
            metadata_extension: actor_metadata(source_event)
          )
        ].freeze
      end

      def target_manifest_digest(context)
        items = context.items.map do |item|
          OperationBatches::ItemV1.new(
            index: item.index,
            command_input: item.submitted_input,
            canonical_input_digest: item.canonical_input_digest
          )
        end
        @manifest_builder.digest(items)
      end

      def batch_fact(context:, event:, markers:, step_name:, metadata_extension: nil)
        TransformedFactV1.new(
          target_stream: context.target_stream,
          event:,
          markers:,
          step_name:,
          metadata_extension:
        )
      end

      def actor_metadata(source_event, **attributes)
        attributes[:policy_version] ||= source_event.metadata["policy_version"]
        MigrationMetadataExtensionV1.new(
          attributed_actor: Commands::Actor.new(
            kind: source_event.metadata.fetch("actor_kind"),
            id: source_event.metadata.fetch("actor_id")
          ),
          **attributes
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "OperationBatch transformation is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
