# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class WorkIntentionV1Transformer
      include Dry::Monads[:result]

      LEGACY_PURPOSE = "Historical exclusive work intention"

      def initialize(
        event_store:,
        context_resolver:,
        repository_marker_builder: RepositoryMarkerBuilder.new
      )
        @event_store = event_store
        @context_resolver = context_resolver
        @repository_marker_builder = repository_marker_builder
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        if source_payload.is_a?(Events::ResourceBoundaryEpochRolledV2)
          validate_boundary!(source_event, source_payload, source_upper_position:)
          return Success([].freeze)
        end

        resolved = @context_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_payload:
        )
        return resolved if resolved.failure?

        context = resolved.value!
        facts =
          case source_payload
          when Events::ResourceLeaseAcquiredV2
            [ declaration_fact(context, source_event, source_payload) ]
          when Events::ResourceLeaseRenewedV2
            [ renewal_fact(context, source_event, source_payload) ]
          when Events::ResourceLeaseReleasedV2
            [ withdrawal_fact(context, source_event, source_payload) ]
          when Events::ResourceLeaseExpiredV2
            [ expiry_fact(context, source_event, source_payload) ]
          when Events::WriteSetReservedV2
            reservation_facts(context, source_event)
          when Events::WriteSetExpandedV2
            membership_facts(context, source_event, prefix: "expand")
          when Events::WriteSetRenewedV2, Events::WriteSetReleasedV2
            []
          end
        Success(facts.freeze)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def declaration_fact(context, source_event, source)
        member = sole_member(context)
        fact(
          target_stream: member.target_stream,
          event: Events::ResourceWorkIntentionDeclaredV1.new(
            intention_id: member.intention_id,
            set_id: context.set_id,
            resource_id: member.resource_id,
            repository_id: context.repository_id,
            change_set_id: context.change_set_id,
            work_item_id: context.work_item_id,
            attempt_id: context.attempt_id,
            agent_id: source.agent_id,
            mode: source.mode,
            purpose: LEGACY_PURPOSE,
            context: nil,
            object_format: source.object_format,
            base_commit_oid: source.base_commit_oid,
            base_blob_oid: source.base_blob_oid,
            fencing_token: source.fencing_token,
            expires_at: source.expires_at
          ),
          markers: member_markers(context, member, include_boundary: true),
          step_name: "declare-work-intention",
          metadata_extension: actor_metadata(source_event, policy_version: source.policy_version)
        )
      end

      def renewal_fact(context, source_event, source)
        member = sole_member(context)
        fact(
          target_stream: member.target_stream,
          event: Events::ResourceWorkIntentionRenewedV1.new(
            intention_id: member.intention_id,
            resource_id: member.resource_id,
            fencing_token: source.fencing_token,
            expires_at: source.expires_at
          ),
          markers: member_markers(context, member, include_boundary: true),
          step_name: "renew-work-intention",
          metadata_extension: actor_metadata(source_event, policy_version: source.policy_version)
        )
      end

      def withdrawal_fact(context, source_event, source)
        member = sole_member(context)
        fact(
          target_stream: member.target_stream,
          event: Events::ResourceWorkIntentionWithdrawnV1.new(
            intention_id: member.intention_id,
            resource_id: member.resource_id,
            fencing_token: source.fencing_token,
            reason: nil
          ),
          markers: member_markers(context, member, include_boundary: true),
          step_name: "withdraw-work-intention",
          metadata_extension: actor_metadata(source_event, policy_version: source.policy_version)
        )
      end

      def expiry_fact(context, source_event, source)
        member = sole_member(context)
        fact(
          target_stream: member.target_stream,
          event: Events::ResourceWorkIntentionExpiredV1.new(
            intention_id: member.intention_id,
            resource_id: member.resource_id,
            fencing_token: source.fencing_token,
            expires_at: source.expires_at
          ),
          markers: member_markers(context, member, include_boundary: true),
          step_name: "expire-work-intention",
          metadata_extension: actor_metadata(source_event, policy_version: source.policy_version)
        )
      end

      def reservation_facts(context, source_event)
        [
          fact(
            target_stream: context.target_set_stream,
            event: Events::WorkIntentionSetCreatedV1.new(
              set_id: context.set_id,
              attempt_id: context.attempt_id,
              work_item_id: context.work_item_id,
              change_set_id: context.change_set_id,
              repository_id: context.repository_id
            ),
            markers: common_markers(context),
            step_name: "create-work-intention-set",
            metadata_extension: actor_metadata(source_event)
          ),
          *membership_facts(context, source_event, prefix: "reserve")
        ]
      end

      def membership_facts(context, source_event, prefix:)
        context.members.each_with_index.map do |member, index|
          fact(
            target_stream: context.target_set_stream,
            event: Events::WorkIntentionAddedToSetV1.new(
              set_id: context.set_id,
              intention_id: member.intention_id,
              resource_id: member.resource_id
            ),
            markers: member_markers(context, member),
            step_name: format("%<prefix>s-work-intention-member-%<position>02d", prefix:, position: index + 1),
            metadata_extension: actor_metadata(source_event)
          )
        end
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

      def fact(target_stream:, event:, markers:, step_name:, metadata_extension:)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension:
        )
      end

      def actor_metadata(source_event, policy_version: nil)
        MigrationMetadataExtensionV1.new(
          attributed_actor: Commands::Actor.new(
            kind: source_event.metadata.fetch("actor_kind"),
            id: source_event.metadata.fetch("actor_id")
          ),
          policy_version: policy_version || source_event.metadata.fetch("policy_version")
        )
      end

      def sole_member(context)
        context.members.sole
      rescue Enumerable::SoleItemExpectedError
        raise ArgumentError, "resource lifecycle transformation requires exactly one member"
      end

      def validate_boundary!(source_event, source, source_upper_position:)
        persisted = @event_store.read_at(
          StreamReference.new(
            context: source_event.stream.context,
            stream_name: source_event.stream.stream_name,
            stream_id: source_event.stream.stream_id
          ),
          source_event.stream_revision
        )
        valid = persisted&.id == source_event.id &&
                source_event.metadata.fetch("schema_version") == source.class.schema_version &&
                source_event.global_position <= source_upper_position &&
                source_event.stream.context == "DevelopmentCoordination" &&
                source_event.stream.stream_name == "ResourceBoundaryEpoch" &&
                source_event.stream.stream_id == source.repository_id &&
                source_event.markers.include?(source.boundary_marker) &&
                source.through_global_position <= source_event.global_position &&
                (!source.previous_through_global_position ||
                  source.previous_through_global_position < source.through_global_position) &&
                source.active_leases.all? { _1.repository_id == source.repository_id }
        raise ArgumentError, "legacy resource-boundary snapshot is inconsistent" unless valid
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "WorkIntention transformation is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
