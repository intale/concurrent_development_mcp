# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class ReleaseSetContextResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        merge_snapshot_context_resolver:,
        merge_reference_resolver:,
        target_event_reference_resolver:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @merge_snapshot_context_resolver = merge_snapshot_context_resolver
        @merge_reference_resolver = merge_reference_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @schema_registry = schema_registry
      end

      def from_preparation(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_preparation:
      )
        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          preparation_event: source_event,
          source_preparation:
        )
      end

      def from_stream(migration_id:, source_config_name:, source_upper_position:, source_event:)
        preparation_event = @event_store.read_at(stream_for(source_event), 0)
        unless preparation_event && preparation_event.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "ReleaseSet preparation is absent from the frozen source range"))
        end

        source_preparation = load(preparation_event)
        unless source_preparation.is_a?(Events::ReleaseSetPreparedV1)
          return Failure(inconsistent(source_event, "ReleaseSet stream does not begin with ReleaseSetPrepared@1"))
        end

        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          preparation_event:,
          source_preparation:
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def load_reference(source_event:, source_upper_position:, source_reference:)
        event = @event_store.read_at(stream_for(source_reference), source_reference.stream_revision)
        unless event && reference_for(event) == source_reference && event.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "referenced event is absent from the frozen source range"))
        end

        Success([ event, load(event) ].freeze)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def target_release_reference(
        migration_id:,
        source_upper_position:,
        source_event:,
        source_reference:,
        context:,
        target_event_type:,
        target_step_name:
      )
        @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream: context.target_stream,
          target_event_type:,
          target_step_name:
        )
      end

      def target_merge_reference(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:
      )
        @merge_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference:
        )
      end

      private

      def resolve(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        preparation_event:,
        source_preparation:
      )
        physical = validate_physical_preparation(
          source_event:,
          preparation_event:,
          source_preparation:,
          source_upper_position:
        )
        return physical if physical.failure?

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: preparation_event,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "ReleaseSet",
          identity_role: "release-set"
        )
        return allocation if allocation.failure?

        change_set = resolve_change_set(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_preparation:
        )
        return change_set if change_set.failure?

        target_change_set_id = change_set.value!.target_stream.stream_id
        members = resolve_members(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_preparation:,
          target_release_set_id: allocation.value!.target_stream.stream_id,
          target_change_set_id:
        )
        return members if members.failure?

        target_stream = allocation.value!.target_stream
        Success(
          ReleaseSetMigrationContextV1.new(
            source_preparation:,
            source_preparation_event: preparation_event,
            target_stream:,
            release_set_id: target_stream.stream_id,
            change_set_id: target_change_set_id,
            members: members.value!
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def resolve_change_set(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_preparation:
      )
        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: "DevelopmentPlanning",
            stream_name: "ChangeSet",
            stream_id: source_preparation.change_set_id
          ),
          target_stream_context: "DevelopmentPlanning",
          target_stream_name: "ChangeSet",
          identity_role: "change-set"
        )
      end

      def resolve_members(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_preparation:,
        target_release_set_id:,
        target_change_set_id:
      )
        members = []
        source_preparation.ordered_members.each_with_index do |source_member, index|
          result = resolve_member(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_member:,
            expected_position: index + 1,
            target_release_set_id:,
            target_change_set_id:
          )
          return result if result.failure?

          members << result.value!
        end
        unless source_preparation.ordered_members.map(&:repository_id).uniq.length == members.length &&
            source_preparation.ordered_members.map(&:merge_snapshot_id).uniq.length == members.length
          return Failure(inconsistent(source_event, "ReleaseSet repeats a repository or MergeSnapshot"))
        end

        Success(members.freeze)
      end

      def resolve_member(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_member:,
        expected_position:,
        target_release_set_id:,
        target_change_set_id:
      )
        snapshot = @merge_snapshot_context_resolver.from_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source_member.snapshot_binding.registration_event
        )
        return snapshot if snapshot.failure?

        snapshot_context = snapshot.value!
        valid = validate_member(
          source_event:,
          source_upper_position:,
          source_member:,
          expected_position:,
          snapshot_context:
        )
        return valid if valid.failure?

        authorization = load_reference(
          source_event:,
          source_upper_position:,
          source_reference: source_member.authorization_event
        )
        return authorization if authorization.failure?

        valid = validate_authorization(
          source_event:,
          source_member:,
          source_authorization: authorization.value!.last
        )
        return valid if valid.failure?

        target_authorization = target_merge_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source_member.authorization_event
        )
        return target_authorization if target_authorization.failure?

        unless snapshot_context.candidate_contexts.all? { _1.change_set_id == target_change_set_id }
          return Failure(inconsistent(source_event, "ReleaseSet member Candidate mappings belong to another ChangeSet"))
        end

        target_member = Events::ReleaseSetMemberAddedV1.new(
          release_set_id: target_release_set_id,
          member_position: source_member.position,
          repository_id: snapshot_context.repository_id,
          merge_snapshot_id: snapshot_context.merge_snapshot_id,
          ordered_candidate_ids: snapshot_context.ordered_candidate_ids,
          authorization_event: target_authorization.value!
        )
        Success(ReleaseSetMemberMigrationV1.new(source_member:, target_member:))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def validate_member(
        source_event:,
        source_upper_position:,
        source_member:,
        expected_position:,
        snapshot_context:
      )
        registration = snapshot_context.source_registration
        verification = load_reference(
          source_event:,
          source_upper_position:,
          source_reference: source_member.snapshot_binding.verification_event
        )
        return verification if verification.failure?

        verified = verification.value!.last
        valid = source_member.position == expected_position &&
                source_member.merge_snapshot_id == registration.merge_snapshot_id &&
                source_member.repository_id == registration.repository_id &&
                source_member.target_branch == registration.target_branch &&
                source_member.object_format == registration.object_format &&
                source_member.target_base_commit_oid == registration.target_base_commit_oid &&
                source_member.merge_commit_oid == registration.merge_commit_oid &&
                source_member.snapshot_binding.registration_event == snapshot_context.source_registration_reference &&
                source_member.snapshot_binding.snapshot_digest == registration.snapshot_digest &&
                source_member.ordered_candidates == registration.ordered_candidates &&
                source_member.change_set_id == registration.ordered_candidates.map(&:change_set_id).uniq.sole &&
                verified.is_a?(Events::MergeSnapshotVerifiedV1) &&
                verified.merge_snapshot_id == registration.merge_snapshot_id &&
                verified.verification_digest == source_member.snapshot_binding.verification_digest
        return Success() if valid

        Failure(inconsistent(source_event, "ReleaseSet member evidence disagrees with its MergeSnapshot history"))
      rescue Enumerable::SoleItemExpectedError
        Failure(inconsistent(source_event, "ReleaseSet member MergeSnapshot does not belong to one ChangeSet"))
      end

      def validate_authorization(source_event:, source_member:, source_authorization:)
        valid = source_authorization.is_a?(Events::MergeAuthorizationGrantedV1) &&
                source_authorization.authorization_id == source_member.authorization_event.stream_id &&
                source_authorization.merge_snapshot_id == source_member.merge_snapshot_id &&
                source_authorization.snapshot_binding == source_member.snapshot_binding &&
                source_authorization.decision_digest == source_member.authorization_decision_digest
        return Success() if valid

        Failure(inconsistent(source_event, "ReleaseSet member authorization evidence is inconsistent"))
      end

      def validate_physical_preparation(
        source_event:,
        preparation_event:,
        source_preparation:,
        source_upper_position:
      )
        stream = stream_for(preparation_event)
        valid = preparation_event.type == "ReleaseSetPrepared" &&
                preparation_event.metadata.fetch("schema_version") == 1 &&
                preparation_event.global_position <= source_upper_position &&
                preparation_event.stream_revision.zero? &&
                stream.context == "DevelopmentIntegration" &&
                stream.stream_name == "ReleaseSet" &&
                stream.stream_id == source_preparation.release_set_id &&
                preparation_event.markers.include?("release-set:#{source_preparation.release_set_id}") &&
                source_preparation.ordered_members.map(&:change_set_id).uniq == [ source_preparation.change_set_id ]
        return Success() if valid

        Failure(inconsistent(source_event, "ReleaseSet identity, schema, stream, revision, markers, or ChangeSet is invalid"))
      end

      def stream_for(value)
        stream = value.respond_to?(:stream) ? value.stream : value
        StreamReference.new(
          context: stream.respond_to?(:context) ? stream.context : value.stream_context,
          stream_name: stream.respond_to?(:stream_name) ? stream.stream_name : value.stream_name,
          stream_id: stream.respond_to?(:stream_id) ? stream.stream_id : value.stream_id
        )
      end

      def reference_for(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "ReleaseSet source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
