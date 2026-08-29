# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class WriteSetExpansionEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::ExpandWriteSet))
        required(:attempt_state).value(Types.Instance(Domain::Attempts::State))
        required(:requested_observations).array(Types.Instance(RequestedLeaseObservationV2))
        required(:expanded_at).filled(:string)
      end

      rule(:plan, :command, :attempt_state, :requested_observations, :expanded_at) do
        plan = values[:plan]
        command = values[:command]
        attempt_state = values[:attempt_state]
        observations = additions(
          attempt_state:,
          requested_observations: values[:requested_observations]
        )
        acquisitions = plan.events.first(observations.length)
        expansion = plan.events.last
        expected_streams = observations.map do |observation|
          StreamFactory.new.resource_lease(observation.resource.resource_id)
        end + [ StreamFactory.new.attempt(command.attempt_id) ]

        unless plan.writes.length == observations.length + 1 &&
               plan.writes.map(&:stream) == expected_streams &&
               acquisitions.all? { _1.is_a?(Events::ResourceLeaseAcquiredV2) } &&
               expansion.is_a?(Events::WriteSetExpandedV2)
          key(:plan).failure("must contain ordered new resource acquisitions followed by one Attempt expansion")
          next
        end

        verify_acquisitions(
          acquisitions:,
          observations:,
          attempt_state:,
          command:,
          expanded_at: values[:expanded_at]
        )
        verify_expansion(
          expansion:,
          acquisitions:,
          attempt_state:,
          command:,
          expanded_at: values[:expanded_at]
        )
      end

      private

      def additions(attempt_state:, requested_observations:)
        current_ids = attempt_state.lease_resources.map(&:resource_id)
        requested_observations.reject do |observation|
          current_ids.include?(observation.resource.resource_id)
        end
      end

      def verify_acquisitions(acquisitions:, observations:, attempt_state:, command:, expanded_at:)
        valid = acquisitions.each_with_index.all? do |event, index|
          observation = observations.fetch(index)
          prepared = observation.prepared_target
          resource = observation.resource

          event.lease_id == prepared.lease_id &&
            event.lease_set_id == command.lease_set_id &&
            event.resource_id == resource.resource_id &&
            event.resource_path == resource.path &&
            event.base_blob_oid == resource.base_blob_oid &&
            event.change_set_id == command.change_set_id &&
            event.work_item_id == command.work_item_id &&
            event.attempt_id == command.attempt_id &&
            event.agent_id == command.actor.id &&
            event.repository_id == command.repository_id &&
            event.base_commit_oid == command.base_commit_oid &&
            event.fencing_token == observation.state.next_fencing_token &&
            event.acquired_at == expanded_at &&
            event.expires_at == attempt_state.lease_expires_at
        end
        key(:plan).failure("must preserve normalized additions, scope, bases, tokens, IDs, and deadline") unless valid
      end

      def verify_expansion(expansion:, acquisitions:, attempt_state:, command:, expanded_at:)
        references = acquisitions.map { lease_reference(_1) }
        valid = expansion.lease_set_id == command.lease_set_id &&
          expansion.change_set_id == command.change_set_id &&
          expansion.work_item_id == command.work_item_id &&
          expansion.attempt_id == command.attempt_id &&
          expansion.repository_id == command.repository_id &&
          expansion.policy_version == attempt_state.lease_policy_version &&
          expansion.added_resources == references &&
          expansion.resource_count == attempt_state.lease_resources.length + references.length &&
          expansion.expanded_at == expanded_at &&
          expansion.expires_at == attempt_state.lease_expires_at
        key(:plan).failure("must summarize only additions and preserve the current lease-set deadline") unless valid
      end

      def lease_reference(event)
        LeaseReferenceV2.new(
          lease_id: event.lease_id,
          resource_id: event.resource_id,
          resource_kind: event.resource_kind,
          resource_path: event.resource_path,
          base_blob_oid: event.base_blob_oid,
          fencing_token: event.fencing_token
        )
      end
    end
  end
end
