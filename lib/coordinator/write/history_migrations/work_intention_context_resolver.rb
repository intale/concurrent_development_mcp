# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class WorkIntentionContextResolver
      include Dry::Monads[:result]

      SOURCE_CLASSES = {
        "ResourceLeaseAcquired" => Events::ResourceLeaseAcquiredV2,
        "ResourceLeaseRenewed" => Events::ResourceLeaseRenewedV2,
        "ResourceLeaseReleased" => Events::ResourceLeaseReleasedV2,
        "ResourceLeaseExpired" => Events::ResourceLeaseExpiredV2,
        "WriteSetReserved" => Events::WriteSetReservedV2,
        "WriteSetExpanded" => Events::WriteSetExpandedV2,
        "WriteSetRenewed" => Events::WriteSetRenewedV2,
        "WriteSetReleased" => Events::WriteSetReleasedV2
      }.freeze
      SET_MEMBERSHIP_TYPES = %w[WriteSetReserved WriteSetExpanded].freeze
      SET_MEMBERSHIP_MAXIMUM_COUNT = WorkIntentionPolicyV1::MAXIMUM_SET_SIZE + 1

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        repository_marker_builder: RepositoryMarkerBuilder.new,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @repository_marker_builder = repository_marker_builder
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        validate_envelope!(source_event, source_payload, source_upper_position:)
        set_state = source_set_state(
          source_event,
          source_payload,
          source_upper_position:
        )
        validate_source_lifecycle!(
          source_event,
          source_payload,
          set_state:,
          source_upper_position:
        )

        context = target_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_payload,
          set_state:
        )
        context.failure? ? context : Success(context.value!)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error,
             EventHistoryLimitExceeded => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def validate_envelope!(source_event, source, source_upper_position:)
        expected_class = SOURCE_CLASSES.fetch(source_event.type)
        persisted = @event_store.read_at(stream_for(source_event), source_event.stream_revision)
        valid = source.is_a?(expected_class) &&
                persisted&.id == source_event.id &&
                source_event.metadata.fetch("schema_version") == expected_class.schema_version &&
                source_event.global_position <= source_upper_position &&
                source_event.markers.include?("command:#{source_event.metadata.fetch('command_id')}")
        valid &&= source_stream_matches?(source_event, source)
        raise ArgumentError, "work-intention source identity, schema, or stream is inconsistent" unless valid

        required = [
          "change-set:#{source.change_set_id}",
          "work-item:#{source.work_item_id}",
          "attempt:#{source.attempt_id}",
          "lease-set:#{source.lease_set_id}",
          "repository:#{source.repository_id}"
        ]
        if lease_event?(source)
          required.concat([
            "resource:#{source.resource_id}",
            "resource-kind:#{source.resource_kind}"
          ])
        end
        unless (required - source_event.markers).empty?
          raise ArgumentError, "work-intention source markers are inconsistent"
        end
      end

      def source_set_state(source_event, source, source_upper_position:)
        events = @event_store.read(
          attempt_stream(source.attempt_id),
          EventReadCriteria.new(
            event_types: SET_MEMBERSHIP_TYPES,
            maximum_count: SET_MEMBERSHIP_MAXIMUM_COUNT,
            direction: :asc
          )
        ).select do |event|
          event.global_position <= source_upper_position &&
            (!write_set_event?(source) || event.stream_revision <= source_event.stream_revision)
        end

        reservation_event = nil
        reservation = nil
        memberships = []
        events.each do |event|
          payload = load(event)
          next unless payload.lease_set_id == source.lease_set_id

          validate_set_event!(event, payload, source:)
          case payload
          when Events::WriteSetReservedV2
            raise ArgumentError, "duplicate legacy write-set reservation" if reservation

            reservation_event = event
            reservation = payload
            memberships = payload.resources.map do |reference|
              membership(reference, event, source_upper_position:)
            end
          when Events::WriteSetExpandedV2
            raise ArgumentError, "write-set expansion precedes its reservation" unless reservation

            additions = payload.added_resources.map do |reference|
              membership(reference, event, source_upper_position:)
            end
            duplicate = additions.find do |addition|
              memberships.any? do |existing|
                existing.reference.lease_id == addition.reference.lease_id ||
                  existing.reference.resource_id == addition.reference.resource_id
              end
            end
            raise ArgumentError, "write-set expansion duplicates a member" if duplicate

            memberships.concat(additions)
            unless payload.resource_count == memberships.length
              raise ArgumentError, "write-set expansion count disagrees with membership history"
            end
          end
        end
        unless reservation_event && reservation
          raise ArgumentError, "legacy write-set reservation is absent from the frozen source range"
        end

        state = LegacyWorkIntentionSetStateV1.new(
          source_set_id: source.lease_set_id,
          reservation_event:,
          reservation:,
          memberships:
        )
        validate_set_source!(source_event, source, state:)
        state
      end

      def validate_set_event!(event, payload, source:)
        valid = event.metadata.fetch("schema_version") == payload.class.schema_version &&
                event.stream.context == "DevelopmentExecution" &&
                event.stream.stream_name == "Attempt" &&
                event.stream.stream_id == source.attempt_id &&
                event.markers.include?("lease-set:#{source.lease_set_id}") &&
                same_scope?(payload, source)
        raise ArgumentError, "legacy write-set membership history is inconsistent" unless valid
      end

      def validate_set_source!(source_event, source, state:)
        if source.is_a?(Events::WriteSetReservedV2)
          unless state.reservation_event.id == source_event.id &&
                 references_equal?(state.reservation.resources, source.resources)
            raise ArgumentError, "write-set reservation does not define the resolved set"
          end
        elsif source.is_a?(Events::WriteSetExpandedV2)
          additions = state.memberships.select { _1.membership_event.id == source_event.id }
          unless references_equal?(additions.map(&:reference), source.added_resources)
            raise ArgumentError, "write-set expansion does not define the resolved additions"
          end
        elsif source.is_a?(Events::WriteSetRenewedV2) || source.is_a?(Events::WriteSetReleasedV2)
          unless source.resource_count == state.memberships.length &&
                 references_equal?(state.memberships.map(&:reference), source.resources)
            raise ArgumentError, "write-set lifecycle snapshot disagrees with membership history"
          end
        else
          member = state.membership(source.lease_id)
          unless member && reference_equal?(member.reference, reference_for(source))
            raise ArgumentError, "resource lease is absent from its write-set membership history"
          end
        end
      end

      def membership(reference, membership_event, source_upper_position:)
        events = @event_store.read_marked(
          resource_lease_stream(reference.resource_id),
          MarkedEventReadCriteria.new(
            event_type: "ResourceLeaseAcquired",
            marker: "lease-set:#{load(membership_event).lease_set_id}",
            maximum_count: 1,
            direction: :asc
          )
        ).select { _1.global_position <= source_upper_position }
        event = events.sole
        acquisition = load(event)
        valid = acquisition.is_a?(Events::ResourceLeaseAcquiredV2) &&
                reference_equal?(reference, reference_for(acquisition)) &&
                same_scope?(acquisition, load(membership_event)) &&
                event.metadata.fetch("command_id") == membership_event.metadata.fetch("command_id") &&
                event.markers.include?("command:#{membership_event.metadata.fetch('command_id')}")
        raise ArgumentError, "write-set member acquisition is absent or inconsistent" unless valid

        LegacyWorkIntentionMembershipV1.new(
          reference:,
          membership_event:,
          acquisition_event: event,
          acquisition:
        )
      rescue Enumerable::SoleItemExpectedError
        raise ArgumentError, "write-set member acquisition is absent or ambiguous"
      end

      def validate_source_lifecycle!(source_event, source, set_state:, source_upper_position:)
        case source
        when Events::ResourceLeaseAcquiredV2
          member = set_state.membership(source.lease_id)
          raise ArgumentError, "lease acquisition does not match its set member" unless
            member&.acquisition_event&.id == source_event.id
        when Events::ResourceLeaseRenewedV2
          validate_resource_lifecycle_aggregate!(
            source_event,
            source,
            aggregate_type: "WriteSetRenewed",
            source_upper_position:
          )
        when Events::ResourceLeaseReleasedV2
          validate_resource_lifecycle_aggregate!(
            source_event,
            source,
            aggregate_type: "WriteSetReleased",
            source_upper_position:
          )
        when Events::ResourceLeaseExpiredV2
          validate_expiry!(source_event, source, set_state:)
        when Events::WriteSetRenewedV2
          validate_write_set_fanout!(source_event, source, event_type: "ResourceLeaseRenewed")
        when Events::WriteSetReleasedV2
          validate_write_set_fanout!(source_event, source, event_type: "ResourceLeaseReleased")
        end
      end

      def validate_resource_lifecycle_aggregate!(
        source_event,
        source,
        aggregate_type:,
        source_upper_position:
      )
        event = @event_store.read_marked(
          attempt_stream(source.attempt_id),
          MarkedEventReadCriteria.new(
            event_type: aggregate_type,
            marker: "command:#{source_event.metadata.fetch('command_id')}",
            maximum_count: 1,
            direction: :asc
          )
        ).find { _1.global_position <= source_upper_position }
        aggregate = event && load(event)
        reference = aggregate&.resources&.find { _1.lease_id == source.lease_id }
        valid = aggregate && same_scope?(aggregate, source) &&
                reference && reference_equal?(reference, reference_for(source)) &&
                lifecycle_times_equal?(source, aggregate)
        raise ArgumentError, "resource lifecycle event has no matching set-level source fact" unless valid
      end

      def validate_write_set_fanout!(source_event, source, event_type:)
        source.resources.each do |reference|
          event = @event_store.read_marked(
            resource_lease_stream(reference.resource_id),
            MarkedEventReadCriteria.new(
              event_type:,
              marker: "command:#{source_event.metadata.fetch('command_id')}",
              maximum_count: 1,
              direction: :asc
            )
          ).sole
          lifecycle = load(event)
          valid = same_scope?(lifecycle, source) &&
                  reference_equal?(reference_for(lifecycle), reference) &&
                  lifecycle_times_equal?(lifecycle, source)
          raise ArgumentError, "write-set lifecycle fanout is incomplete or inconsistent" unless valid
        end
      rescue Enumerable::SoleItemExpectedError
        raise ArgumentError, "write-set lifecycle fanout is incomplete or ambiguous"
      end

      def validate_expiry!(source_event, source, set_state:)
        member = set_state.membership(source.lease_id)
        renewal = @event_store.read_latest_marked(
          resource_lease_stream(source.resource_id),
          LatestMarkedEventReadCriteria.new(
            event_type: "ResourceLeaseRenewed",
            marker: "lease-set:#{source.lease_set_id}"
          )
        ).find { _1.global_position < source_event.global_position }
        current = renewal ? load(renewal) : member&.acquisition
        terminal = @event_store.read_marked(
          resource_lease_stream(source.resource_id),
          MarkedEventReadCriteria.new(
            event_type: "ResourceLeaseReleased",
            marker: "lease-set:#{source.lease_set_id}",
            maximum_count: 1,
            direction: :asc
          )
        ).find { _1.global_position <= source_event.global_position }
        valid = current && terminal.nil? &&
                current.lease_id == source.lease_id &&
                current.fencing_token == source.fencing_token &&
                current.expires_at == source.expires_at
        raise ArgumentError, "resource lease expiry disagrees with its prior lifecycle" unless valid
      end

      def target_context(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        set_state:
      )
        set = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: set_state.reservation_event,
          target_stream_context: "DevelopmentCoordination",
          target_stream_name: "WorkIntentionSet",
          identity_role: "work-intention-set:#{source.lease_set_id}"
        )
        return set if set.failure?

        repository = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentPlanning",
          source_name: "Repository",
          source_id: source.repository_id,
          target_context: "DevelopmentPlanning",
          target_name: "Repository",
          identity_role: "repository"
        )
        return repository if repository.failure?

        change_set = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentPlanning",
          source_name: "ChangeSet",
          source_id: source.change_set_id,
          target_context: "DevelopmentPlanning",
          target_name: "ChangeSet",
          identity_role: "change-set"
        )
        return change_set if change_set.failure?

        work_item = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentExecution",
          source_name: "WorkItem",
          source_id: source.work_item_id,
          target_context: "DevelopmentExecution",
          target_name: "WorkItem",
          identity_role: "work-item"
        )
        return work_item if work_item.failure?

        attempt = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentExecution",
          source_name: "Attempt",
          source_id: source.attempt_id,
          target_context: "DevelopmentExecution",
          target_name: "Attempt",
          identity_role: "attempt"
        )
        return attempt if attempt.failure?

        selected = selected_memberships(source, set_state:)
        members = []
        selected.each do |membership|
          migrated = target_member(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            membership:
          )
          return migrated if migrated.failure?

          members << migrated.value!
        end
        repository_id = repository.value!.target_stream.stream_id
        Success(
          WorkIntentionMigrationContextV1.new(
            target_set_stream: set.value!.target_stream,
            set_id: set.value!.target_stream.stream_id,
            repository_id:,
            change_set_id: change_set.value!.target_stream.stream_id,
            work_item_id: work_item.value!.target_stream.stream_id,
            attempt_id: attempt.value!.target_stream.stream_id,
            repository_markers: repository_markers(
              source.repository_id,
              target_repository_id: repository_id,
              source_upper_position:
            ),
            members:
          )
        )
      end

      def target_member(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        membership:
      )
        source = membership.acquisition
        intention = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: membership.acquisition_event,
          target_stream_context: "DevelopmentCoordination",
          target_stream_name: "ResourceWorkIntention",
          identity_role: "work-intention:#{source.lease_id}"
        )
        return intention if intention.failure?

        resource = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentCoordination",
          source_name: "Resource",
          source_id: source.resource_id,
          target_context: "DevelopmentCoordination",
          target_name: "Resource",
          identity_role: "resource"
        )
        return resource if resource.failure?

        target_stream = intention.value!.target_stream
        Success(
          WorkIntentionMemberMigrationV1.new(
            target_stream:,
            intention_id: target_stream.stream_id,
            resource_id: resource.value!.target_stream.stream_id,
            resource_kind: source.resource_kind,
            resource_path: source.resource_path,
            base_blob_oid: source.base_blob_oid,
            fencing_token: source.fencing_token
          )
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
        target_context:,
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
          target_stream_context: target_context,
          target_stream_name: target_name,
          identity_role:
        )
      end

      def repository_markers(source_repository_id, target_repository_id:, source_upper_position:)
        event = @event_store.read_at(
          StreamReference.new(
            context: "DevelopmentPlanning",
            stream_name: "Repository",
            stream_id: source_repository_id
          ),
          0
        )
        source = event && load(event)
        valid = event && event.global_position <= source_upper_position &&
                source.is_a?(Events::RepositoryRegisteredV1) &&
                source.repository_id == source_repository_id
        raise ArgumentError, "legacy Repository registration is absent or inconsistent" unless valid

        registration = RepositoryRegistrationV2.new(
          repository_id: target_repository_id,
          scope: source.scope,
          repository_key: source.repository_key,
          display_name: nil,
          paths: [],
          remotes: []
        )
        @repository_marker_builder.call(registration)
      end

      def selected_memberships(source, set_state:)
        references = references_for(source)
        references.map do |reference|
          membership = set_state.membership(reference.lease_id)
          unless membership && reference_equal?(membership.reference, reference)
            raise ArgumentError, "legacy write-set member cannot be resolved"
          end

          membership
        end
      end

      def references_for(source)
        case source
        when Events::WriteSetReservedV2,
             Events::WriteSetRenewedV2,
             Events::WriteSetReleasedV2
          source.resources
        when Events::WriteSetExpandedV2
          source.added_resources
        else
          [ reference_for(source) ]
        end
      end

      def reference_for(source)
        LeaseReferenceV2.new(
          lease_id: source.lease_id,
          resource_id: source.resource_id,
          resource_kind: source.resource_kind,
          resource_path: source.resource_path,
          base_blob_oid: source.base_blob_oid,
          fencing_token: source.fencing_token
        )
      end

      def same_scope?(left, right)
        %i[
          lease_set_id change_set_id work_item_id attempt_id repository_id policy_version
        ].all? { left.public_send(_1) == right.public_send(_1) }
      end

      def lifecycle_times_equal?(lease, aggregate)
        case lease
        when Events::ResourceLeaseRenewedV2
          lease.renewed_at == aggregate.renewed_at &&
            lease.previous_expires_at == aggregate.previous_expires_at &&
            lease.expires_at == aggregate.expires_at
        when Events::ResourceLeaseReleasedV2
          lease.previous_expires_at == aggregate.previous_expires_at &&
            lease.released_at == aggregate.released_at
        else
          false
        end
      end

      def reference_equal?(left, right)
        left.to_h == right.to_h
      end

      def references_equal?(left, right)
        normalize_references(left) == normalize_references(right)
      end

      def normalize_references(references)
        references.map(&:to_h).sort_by do |reference|
          [ reference.fetch(:resource_id), reference.fetch(:lease_id) ]
        end
      end

      def lease_event?(source)
        source.is_a?(Events::ResourceLeaseAcquiredV2) ||
          source.is_a?(Events::ResourceLeaseRenewedV2) ||
          source.is_a?(Events::ResourceLeaseReleasedV2) ||
          source.is_a?(Events::ResourceLeaseExpiredV2)
      end

      def source_stream_matches?(source_event, source)
        if lease_event?(source)
          source_event.stream.context == "DevelopmentCoordination" &&
            source_event.stream.stream_name == "ResourceLease" &&
            source_event.stream.stream_id == source.resource_id
        else
          source_event.stream.context == "DevelopmentExecution" &&
            source_event.stream.stream_name == "Attempt" &&
            source_event.stream.stream_id == source.attempt_id
        end
      end

      def write_set_event?(source)
        !lease_event?(source)
      end

      def attempt_stream(attempt_id)
        StreamReference.new(
          context: "DevelopmentExecution",
          stream_name: "Attempt",
          stream_id: attempt_id
        )
      end

      def resource_lease_stream(resource_id)
        StreamReference.new(
          context: "DevelopmentCoordination",
          stream_name: "ResourceLease",
          stream_id: resource_id
        )
      end

      def stream_for(event)
        StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
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
          message: "WorkIntention transformation is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
