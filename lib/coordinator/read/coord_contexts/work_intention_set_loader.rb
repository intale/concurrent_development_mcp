# frozen_string_literal: true

module Coordinator::Read
  module CoordContexts
    class WorkIntentionSetLoader
      Member = Data.define(:state, :history, :declaration_event, :resource)

      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(event, payload)
        trigger = @event_store.read_at(
          @stream_factory.resource_work_intention(payload.intention_id), event.stream_revision
        )
        unless trigger&.id == event.id
          raise InvalidProjectionSource, "Work-intention trigger is absent from its source stream"
        end

        triggering_history = intention_history(payload.intention_id)
        declaration_event, declaration = declaration_pair(triggering_history)

        set_events = @event_store.read(
          @stream_factory.work_intention_set(declaration.set_id),
          Coordinator::Write::EventQueries::WORK_INTENTION_SET_STATE
        )
        created_event = set_events.find { _1.type == "WorkIntentionSetCreated" }
        raise InvalidProjectionSource, "Work-intention set is missing its creation fact" unless created_event

        created = load_event(created_event)
        memberships = set_events.select { _1.type == "WorkIntentionAddedToSet" }.map { load_event(_1) }
        raise InvalidProjectionSource, "Work-intention set has no members" if memberships.empty?

        members = memberships.map { load_member(_1, set_id: created.set_id) }
        verify_set!(created, members)
        build_view(created_event:, created:, members:)
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def load_member(membership, set_id:)
        history = intention_history(membership.intention_id)
        declaration_event, declaration = declaration_pair(history)
        unless declaration.set_id == set_id && declaration.resource_id == membership.resource_id
          raise InvalidProjectionSource, "Work-intention membership is inconsistent"
        end

        state = WorkIntentionStateV1.reduce(history.map(&:last))
        registration_event = @event_store.read(
          @stream_factory.resource(state.resource_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ "ResourceRegistered" ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        raise InvalidProjectionSource, "Work-intention Resource registration is missing" unless registration_event

        Member.new(
          state:,
          history:,
          declaration_event:,
          resource: load_event(registration_event)
        )
      end

      def intention_history(intention_id)
        @event_store.read_grouped(
          @stream_factory.resource_work_intention(intention_id),
          Coordinator::Write::EventQueries::WORK_INTENTION_STATE
        ).reverse.map { [ _1, load_event(_1) ] }
      end

      def declaration_pair(history)
        pair = history.find do |_physical, logical|
          logical.is_a?(Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1)
        end
        raise InvalidProjectionSource, "Work intention is missing its declaration fact" unless pair

        pair
      end

      def verify_set!(created, members)
        states = members.map(&:state)
        consistent = states.all? do |state|
          state.set_id == created.set_id &&
            state.repository_id == created.repository_id &&
            state.change_set_id == created.change_set_id &&
            state.work_item_id == created.work_item_id &&
            state.attempt_id == created.attempt_id
        end
        raise InvalidProjectionSource, "Work-intention members disagree with their set" unless consistent
        return if states.map(&:agent_id).uniq.one?

        raise InvalidProjectionSource, "Work-intention set has multiple agent attributions"
      end

      def build_view(created_event:, created:, members:)
        declaration_events = members.map(&:declaration_event)
        initial_command_id = created_event.metadata.fetch("command_id")
        expanded_event = declaration_events
          .reject { _1.metadata.fetch("command_id") == initial_command_id }
          .max_by(&:created_at)
        renewed_event = lifecycle_events(members, "ResourceWorkIntentionRenewed").max_by(&:created_at)
        withdrawal_events = lifecycle_events(members, "ResourceWorkIntentionWithdrawn")
        release_event = withdrawal_events.max_by(&:created_at) if withdrawal_events.length == members.length
        expiration_histories = members.map do |member|
          member.history.filter_map do |_physical, logical|
            logical.expires_at if logical.respond_to?(:expires_at)
          end
        end
        current_expirations = expiration_histories.map(&:last)
        previous_expirations = expiration_histories.filter_map { _1[-2] }

        WorkIntentionSetViewV1.new(
          set_id: created.set_id,
          change_set_id: created.change_set_id,
          work_item_id: created.work_item_id,
          attempt_id: created.attempt_id,
          repository_id: created.repository_id,
          agent_id: members.first.state.agent_id,
          policy_version: members.first.declaration_event.metadata.fetch("policy_version"),
          intentions: members.map { reference(_1) }.sort_by { _1.resource_id.b },
          created_event:,
          last_expanded_event: expanded_event,
          last_renewed_event: renewed_event,
          release_event:,
          declared_at: timestamp(created_event),
          last_expanded_at: expanded_event && timestamp(expanded_event),
          last_renewed_at: renewed_event && timestamp(renewed_event),
          previous_expires_at: previous_expirations.min,
          expires_at: current_expirations.min,
          withdrawn_at: release_event && timestamp(release_event)
        )
      end

      def lifecycle_events(members, type)
        members.flat_map do |member|
          member.history.filter_map { |physical, _logical| physical if physical.type == type }
        end
      end

      def reference(member)
        WorkIntentionViewV1.new(
          intention_id: member.state.intention_id,
          resource_id: member.state.resource_id,
          resource_kind: member.resource.kind,
          resource_path: member.resource.normalized_path,
          base_blob_oid: member.state.base_blob_oid,
          mode: member.state.mode,
          purpose: member.state.purpose,
          context: member.state.context,
          fencing_token: member.state.fencing_token
        )
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def timestamp(event)
        event.created_at.utc.iso8601(6)
      end
    end
  end
end
