# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class WorkIntentionSetEvidenceLoader
      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(set_id, excluding_event_ids: [])
        set_events = @event_store.read(
          @stream_factory.work_intention_set(set_id),
          Coordinator::Write::EventQueries::WORK_INTENTION_SET_STATE
        )
        created_event = set_events.find { _1.type == "WorkIntentionSetCreated" }
        raise InvalidProjectionSource, "Work-intention set is missing its creation fact" unless created_event

        created = load_event(created_event)
        memberships = set_events.select { _1.type == "WorkIntentionAddedToSet" }.map { load_event(_1) }
        unless created.set_id == set_id && memberships.length.positive?
          raise InvalidProjectionSource, "Work-intention set evidence is incomplete"
        end

        members = memberships.map do |membership|
          load_member(
            membership,
            set_id:,
            excluding_event_ids:
          )
        end
        WorkIntentionSetEvidenceV1.new(
          set_id:,
          repository_id: created.repository_id,
          resources: members.map(&:reference),
          created_at: created_event.created_at.utc.iso8601(6),
          current_expires_at: members.map(&:current_expires_at).min,
          before_command_expires_at: before_command_expiration(members)
        )
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      def member_count_for_attempt(attempt_id)
        created_event = @event_store.read_global_marked(
          Coordinator::Write::EventQueries.work_intention_set_for_attempt("attempt:#{attempt_id}")
        ).first
        return 0 unless created_event

        created = load_event(created_event)
        set_events = @event_store.read(
          @stream_factory.work_intention_set(created.set_id),
          Coordinator::Write::EventQueries::WORK_INTENTION_SET_STATE
        )
        memberships = set_events.select { _1.type == "WorkIntentionAddedToSet" }.map { load_event(_1) }
        unless created.attempt_id == attempt_id && memberships.all? { _1.set_id == created.set_id }
          raise InvalidProjectionSource, "Work-intention set does not match its Attempt index"
        end

        memberships.length
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def load_member(membership, set_id:, excluding_event_ids:)
        history = @event_store.read_grouped(
          @stream_factory.resource_work_intention(membership.intention_id),
          Coordinator::Write::EventQueries::WORK_INTENTION_STATE
        ).reverse
        facts = history.map { [ _1, load_event(_1) ] }
        _declaration_event, declaration = facts.find do |_physical, payload|
          payload.is_a?(Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1)
        end
        unless declaration && declaration.set_id == set_id &&
               declaration.intention_id == membership.intention_id &&
               declaration.resource_id == membership.resource_id
          raise InvalidProjectionSource, "Work-intention membership is inconsistent"
        end

        expiration_facts = facts.select { |_physical, payload| payload.respond_to?(:expires_at) }
        current = expiration_facts.last&.last&.expires_at
        before = expiration_facts.reject { |physical, _payload| excluding_event_ids.include?(physical.id) }
          .last&.last&.expires_at
        WorkIntentionMemberEvidenceV1.new(
          reference: lease_reference(declaration),
          current_expires_at: current,
          before_command_expires_at: before
        )
      end

      def lease_reference(declaration)
        event = @event_store.read(
          @stream_factory.resource(declaration.resource_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ "ResourceRegistered" ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        raise InvalidProjectionSource, "Work-intention Resource registration is missing" unless event

        registration = load_event(event)
        Coordinator::Write::LeaseReferenceV2.new(
          lease_id: declaration.intention_id,
          resource_id: declaration.resource_id,
          resource_kind: registration.kind,
          resource_path: registration.normalized_path,
          base_blob_oid: declaration.base_blob_oid,
          fencing_token: declaration.fencing_token
        )
      end

      def before_command_expiration(members)
        values = members.map(&:before_command_expires_at)
        values.min if values.all?
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
