# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelWorkIntentionTransformer
      include Dry::Monads[:result]

      def initialize(
        context_resolver:,
        repository_marker_builder: RepositoryMarkerBuilder.new
      )
        @context_resolver = context_resolver
        @repository_marker_builder = repository_marker_builder
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        case source_payload
        when Events::WorkIntentionSetCreatedV1
          set_created(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::WorkIntentionAddedToSetV1
          member_added(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::ResourceWorkIntentionDeclaredV1,
             Events::ResourceWorkIntentionRenewedV1,
             Events::ResourceWorkIntentionWithdrawnV1,
             Events::ResourceWorkIntentionExpiredV1
          intention_fact(
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

      def set_created(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        context = set_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_set_id: source.set_id
        )
        return context if context.failure?

        set = context.value!
        Success([
          fact(
            target_stream: set.target_stream,
            event: Events::WorkIntentionSetCreatedV1.new(
              set_id: set.set_id,
              attempt_id: set.attempt_id,
              work_item_id: set.work_item_id,
              change_set_id: set.change_set_id,
              repository_id: set.repository_id
            ),
            markers: common_markers(set),
            step_name: "create-work-intention-set",
            source_event:
          )
        ])
      end

      def member_added(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        set = set_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_set_id: source.set_id
        )
        return set if set.failure?

        intention = intention_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_intention_id: source.intention_id
        )
        return intention if intention.failure?

        context = set.value!
        member = intention.value!
        unless member.set.set_id == context.set_id && member.resource_id == mapped_resource_id(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_resource_id: source.resource_id
        )
          return Failure(invalid(source_event, "work-intention membership disagrees with its declaration"))
        end

        Success([
          fact(
            target_stream: context.target_stream,
            event: Events::WorkIntentionAddedToSetV1.new(
              set_id: context.set_id,
              intention_id: member.intention_id,
              resource_id: member.resource_id
            ),
            markers: member_markers(context, member),
            step_name: "add-work-intention-to-set",
            source_event:
          )
        ])
      end

      def intention_fact(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        context = intention_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_intention_id: source.intention_id
        )
        return context if context.failure?

        intention = context.value!
        event, step_name = target_intention_event(source, context: intention)
        Success([
          fact(
            target_stream: intention.target_stream,
            event:,
            markers: member_markers(intention.set, intention, include_boundary: true),
            step_name:,
            source_event:
          )
        ])
      end

      def target_intention_event(source, context:)
        common = {
          intention_id: context.intention_id,
          resource_id: context.resource_id
        }
        case source
        when Events::ResourceWorkIntentionDeclaredV1
          [
            Events::ResourceWorkIntentionDeclaredV1.new(
              **common,
              set_id: context.set.set_id,
              repository_id: context.set.repository_id,
              change_set_id: context.set.change_set_id,
              work_item_id: context.set.work_item_id,
              attempt_id: context.set.attempt_id,
              agent_id: source.agent_id,
              mode: source.mode,
              purpose: source.purpose,
              context: source.context,
              object_format: source.object_format,
              base_commit_oid: source.base_commit_oid,
              base_blob_oid: source.base_blob_oid,
              fencing_token: source.fencing_token,
              expires_at: source.expires_at
            ),
            "declare-work-intention"
          ]
        when Events::ResourceWorkIntentionRenewedV1
          [
            Events::ResourceWorkIntentionRenewedV1.new(
              **common,
              fencing_token: source.fencing_token,
              expires_at: source.expires_at
            ),
            "renew-work-intention"
          ]
        when Events::ResourceWorkIntentionWithdrawnV1
          [
            Events::ResourceWorkIntentionWithdrawnV1.new(
              **common,
              fencing_token: source.fencing_token,
              reason: source.reason
            ),
            "withdraw-work-intention"
          ]
        when Events::ResourceWorkIntentionExpiredV1
          [
            Events::ResourceWorkIntentionExpiredV1.new(
              **common,
              fencing_token: source.fencing_token,
              expires_at: source.expires_at
            ),
            "expire-work-intention"
          ]
        end
      end

      def set_context(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_set_id:
      )
        @context_resolver.set(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_set_id:
        )
      end

      def intention_context(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_intention_id:
      )
        @context_resolver.intention(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_intention_id:
        )
      end

      def mapped_resource_id(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_resource_id:
      )
        result = @context_resolver.resource(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_resource_id:
        )
        raise ArgumentError, result.failure.message if result.failure?

        result.value!.fetch(0)
      end

      def common_markers(context)
        [
          "change-set:#{context.change_set_id}",
          "work-item:#{context.work_item_id}",
          "attempt:#{context.attempt_id}",
          "work-intention-set:#{context.set_id}",
          *context.repository_markers
        ].uniq
      end

      def member_markers(context, member, include_boundary: false)
        markers = common_markers(context) + [
          "resource:#{member.resource_id}",
          "resource-kind:#{member.resource_kind}",
          "work-intention:#{member.intention_id}"
        ]
        if include_boundary
          markers.concat(
            @repository_marker_builder.work_intention_event_markers(
              repository_id: context.repository_id,
              resource_path: member.resource_path
            )
          )
        end
        markers.uniq
      end

      def fact(target_stream:, event:, markers:, step_name:, source_event:)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension: MigrationMetadataExtensionV1.new(
            attributed_actor: Commands::Actor.new(
              kind: source_event.metadata.fetch("actor_kind"),
              id: source_event.metadata.fetch("actor_id")
            ),
            policy_version: source_event.metadata["policy_version"]
          )
        )
      end

      def invalid(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Post-remodel WorkIntention transformation is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
