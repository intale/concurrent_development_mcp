# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class WriteSetReservationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::ReserveWriteSet))
        required(:resources).array(Types.Instance(LeaseResourceV2))
        required(:attempt_stream).value(Types.Instance(StreamReference))
        required(:lease_states).array(Types.Instance(Domain::ResourceLeases::State))
        required(:lease_set_id).filled(:string)
        required(:lease_ids).array(:string)
        required(:acquired_at).filled(:string)
        required(:expires_at).filled(:string)
      end

      rule(
        :plan,
        :command,
        :resources,
        :attempt_stream,
        :lease_states,
        :lease_set_id,
        :lease_ids,
        :acquired_at,
        :expires_at
      ) do
        plan = values[:plan]
        command = values[:command]
        resources = values[:resources]
        acquisitions = plan.events.first(resources.length)
        reservation = plan.events.last
        expected_streams = resources.map do |resource|
          StreamFactory.new.resource_lease(resource.resource_id)
        end + [ values[:attempt_stream] ]

        unless plan.writes.length == resources.length + 1 &&
               plan.writes.map(&:stream) == expected_streams &&
               acquisitions.all? { _1.is_a?(Events::ResourceLeaseAcquiredV2) } &&
               reservation.is_a?(Events::WriteSetReservedV2)
          key(:plan).failure("must contain ordered resource acquisitions followed by one Attempt reservation")
          next
        end

        verify_acquisitions(
          acquisitions:,
          command:,
          resources:,
          states: values[:lease_states],
          lease_set_id: values[:lease_set_id],
          lease_ids: values[:lease_ids],
          acquired_at: values[:acquired_at],
          expires_at: values[:expires_at]
        )
        verify_reservation(
          reservation:,
          acquisitions:,
          command:,
          lease_set_id: values[:lease_set_id],
          acquired_at: values[:acquired_at],
          expires_at: values[:expires_at]
        )
      end

      private

      def verify_acquisitions(
        acquisitions:,
        command:,
        resources:,
        states:,
        lease_set_id:,
        lease_ids:,
        acquired_at:,
        expires_at:
      )
        valid = acquisitions.each_with_index.all? do |event, index|
          resource = resources.fetch(index)
          state = states.fetch(index)

          event.lease_id == lease_ids.fetch(index) &&
            event.lease_set_id == lease_set_id &&
            event.resource_id == resource.resource_id &&
            event.resource_path == resource.path &&
            event.base_blob_oid == resource.base_blob_oid &&
            event.change_set_id == command.change_set_id &&
            event.work_item_id == command.work_item_id &&
            event.attempt_id == command.attempt_id &&
            event.agent_id == command.actor.id &&
            event.repository_id == command.repository_id &&
            event.base_commit_oid == command.base_commit_oid &&
            event.fencing_token == state.next_fencing_token &&
            event.acquired_at == acquired_at &&
            event.expires_at == expires_at
        end
        key(:plan).failure("must preserve normalized resources, scope, bases, tokens, IDs, and times") unless valid
      end

      def verify_reservation(reservation:, acquisitions:, command:, lease_set_id:, acquired_at:, expires_at:)
        references = acquisitions.map do |event|
          LeaseReferenceV2.new(
            lease_id: event.lease_id,
            resource_id: event.resource_id,
            resource_kind: event.resource_kind,
            resource_path: event.resource_path,
            base_blob_oid: event.base_blob_oid,
            fencing_token: event.fencing_token
          )
        end
        valid = reservation.lease_set_id == lease_set_id &&
          reservation.change_set_id == command.change_set_id &&
          reservation.work_item_id == command.work_item_id &&
          reservation.attempt_id == command.attempt_id &&
          reservation.repository_id == command.repository_id &&
          reservation.resources == references &&
          reservation.reserved_at == acquired_at &&
          reservation.expires_at == expires_at &&
          expires_at > acquired_at
        key(:plan).failure("must summarize the complete reservation with a positive duration") unless valid
      end
    end
  end
end
