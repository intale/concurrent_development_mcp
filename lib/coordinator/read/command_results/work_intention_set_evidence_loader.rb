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

      def call(set_id, through_position:, before_position:)
        set_events = set_history(set_id, through_position:)
        created_event = set_events.find { _1.type == "WorkIntentionSetCreated" }
        raise InvalidProjectionSource, "Work-intention set is missing its creation fact" unless created_event

        created = load_event(created_event)
        memberships = memberships_at(set_events, through_position:)
        unless created.set_id == set_id && memberships.length.positive? &&
               memberships.all? { _1.set_id == set_id } &&
               memberships.map(&:intention_id).uniq.length == memberships.length
          raise InvalidProjectionSource, "Work-intention set evidence is incomplete"
        end

        members = memberships.map do |membership|
          load_member(
            membership,
            set_id:,
            repository_id: created.repository_id,
            through_position:,
            before_position:
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

      def member_count_for_attempt(attempt_id, through_position:)
        created_event = @event_store.read_global_marked(
          Coordinator::Write::GlobalMarkedEventReadCriteria.new(
            **Coordinator::Write::EventQueries.work_intention_set_for_attempt("attempt:#{attempt_id}").to_h,
            to_position: through_position
          )
        ).first
        return 0 unless created_event

        created = load_event(created_event)
        set_events = set_history(created.set_id, through_position:)
        memberships = memberships_at(set_events, through_position:)
        unless created.attempt_id == attempt_id && memberships.all? { _1.set_id == created.set_id }
          raise InvalidProjectionSource, "Work-intention set does not match its Attempt index"
        end

        memberships.length
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def memberships_at(set_events, through_position:)
        command_positions = {}
        set_events.select { _1.type == "WorkIntentionAddedToSet" }.filter_map do |event|
          command_id = event.metadata.fetch("command_id")
          position = command_positions.fetch(command_id) do
            command_positions[command_id] = successful_command_position(command_id)
          end
          load_event(event) if position <= through_position
        end
      end

      def successful_command_position(command_id)
        event = @event_store.read(
          @stream_factory.command(command_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ "CommandSucceeded" ], maximum_count: 1, direction: :asc
          )
        ).first
        raise InvalidProjectionSource, "Work-intention membership has no successful producing command" unless event

        event.global_position
      end

      def set_history(set_id, through_position:)
        latest = latest_fact(
          stream_name: "WorkIntentionSet",
          event_types: [ "WorkIntentionSetCreated", "WorkIntentionAddedToSet" ],
          marker: "work-intention-set:#{set_id}",
          through_position:
        )
        unless latest && latest.stream.stream_id == set_id
          raise InvalidProjectionSource, "Work-intention set has no facts at the command position"
        end

        @event_store.read(
          @stream_factory.work_intention_set(set_id),
          Coordinator::Write::EventReadCriteria.new(
            **Coordinator::Write::EventQueries::WORK_INTENTION_SET_STATE.to_h,
            to_revision: latest.stream_revision
          )
        )
      end

      def load_member(membership, set_id:, repository_id:, through_position:, before_position:)
        current_event = expiration_event(membership.intention_id, through_position:)
        unless current_event && current_event.stream.stream_id == membership.intention_id
          raise InvalidProjectionSource, "Work-intention has no deadline at the command position"
        end
        declaration_event = @event_store.read(
          @stream_factory.resource_work_intention(membership.intention_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ "ResourceWorkIntentionDeclared" ], maximum_count: 1,
            direction: :asc, to_revision: current_event.stream_revision
          )
        ).first
        declaration = declaration_event && load_event(declaration_event)
        unless declaration && declaration.set_id == set_id &&
               declaration.intention_id == membership.intention_id &&
               declaration.resource_id == membership.resource_id && declaration.repository_id == repository_id
          raise InvalidProjectionSource, "Work-intention membership is inconsistent"
        end

        previous_event = if current_event.global_position <= before_position
                           current_event
        else
                           expiration_event(membership.intention_id, through_position: before_position)
        end
        WorkIntentionMemberEvidenceV1.new(
          reference: intention_reference(declaration),
          current_expires_at: expiration(current_event, declaration:),
          before_command_expires_at: previous_event && expiration(previous_event, declaration:)
        )
      end

      def expiration_event(intention_id, through_position:)
        return if through_position.negative?

        latest_fact(
          stream_name: "ResourceWorkIntention",
          event_types: [ "ResourceWorkIntentionDeclared", "ResourceWorkIntentionRenewed" ],
          marker: "work-intention:#{intention_id}",
          through_position:
        )
      end

      def latest_fact(stream_name:, event_types:, marker:, through_position:)
        @event_store.read_latest_global_marked(
          Coordinator::Write::GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentCoordination", stream_name:, event_types:,
            markers: [ marker ], maximum_count: 1, direction: :desc, from_position: through_position
          )
        )
      end

      def expiration(event, declaration:)
        fact = load_event(event)
        unless event.stream.stream_id == declaration.intention_id &&
               fact.intention_id == declaration.intention_id && fact.resource_id == declaration.resource_id &&
               fact.fencing_token == declaration.fencing_token
          raise InvalidProjectionSource, "Work-intention deadline does not match its declaration"
        end

        fact.expires_at
      end

      def intention_reference(declaration)
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
        unless registration.resource_id == declaration.resource_id &&
               registration.repository_id == declaration.repository_id
          raise InvalidProjectionSource, "Work-intention Resource registration is inconsistent"
        end
        Coordinator::Write::WorkIntentionReceiptReferenceV1.new(
          intention_id: declaration.intention_id,
          resource_id: declaration.resource_id,
          resource_kind: registration.kind,
          resource_path: registration.normalized_path,
          base_blob_oid: declaration.base_blob_oid,
          mode: declaration.mode,
          purpose: declaration.purpose,
          context: declaration.context,
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
