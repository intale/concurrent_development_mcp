# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class WriteSetReleaseEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::ReleaseLeaseSet))
        required(:attempt_state).value(Types.Instance(Domain::Attempts::State))
        required(:current_observations).array(Types.Instance(CurrentLeaseObservationV1))
        required(:released_at).filled(:string)
      end

      rule(:plan, :command, :attempt_state, :current_observations, :released_at) do
        plan = values[:plan]
        command = values[:command]
        attempt_state = values[:attempt_state]
        observations = values[:current_observations]
        releases = plan.events.first(observations.length)
        write_set_release = plan.events.last
        expected_streams = observations.map do |observation|
          StreamFactory.new.resource_lease(observation.reference.resource_key_hash)
        end + [ StreamFactory.new.attempt(command.attempt_id) ]

        unless plan.writes.length == observations.length + 1 &&
               plan.writes.map(&:stream) == expected_streams &&
               releases.all? { _1.is_a?(Events::ResourceLeaseReleasedV1) } &&
               write_set_release.is_a?(Events::WriteSetReleasedV1)
          key(:plan).failure("must contain ordered resource releases followed by one Attempt set release")
          next
        end

        verify_resource_releases(
          releases:,
          observations:,
          attempt_state:,
          command:,
          released_at: values[:released_at]
        )
        verify_write_set_release(
          release: write_set_release,
          attempt_state:,
          command:,
          released_at: values[:released_at]
        )
      end

      private

      def verify_resource_releases(releases:, observations:, attempt_state:, command:, released_at:)
        snapshot = attempt_state.base_snapshots.first
        valid = releases.each_with_index.all? do |event, index|
          observation = observations.fetch(index)
          reference = observation.reference
          event.lease_id == reference.lease_id &&
            event.lease_set_id == command.lease_set_id &&
            event.resource_key == reference.resource_key &&
            event.resource_key_hash == reference.resource_key_hash &&
            event.resource_kind == reference.resource_kind &&
            event.resource_path == reference.resource_path &&
            event.base_blob_oid == reference.base_blob_oid &&
            event.change_set_id == command.change_set_id &&
            event.work_item_id == command.work_item_id &&
            event.attempt_id == command.attempt_id &&
            event.agent_id == command.actor.id &&
            event.repository_id == attempt_state.lease_repository_id &&
            event.object_format == snapshot.object_format &&
            event.base_commit_oid == snapshot.commit_oid &&
            event.fencing_token == reference.fencing_token &&
            event.acquired_at == observation.state.acquired_at &&
            event.previous_expires_at == attempt_state.lease_expires_at &&
            event.released_at == released_at
        end
        key(:plan).failure("must close every current lease without changing identity or fencing") unless valid
      end

      def verify_write_set_release(release:, attempt_state:, command:, released_at:)
        valid = release.lease_set_id == command.lease_set_id &&
          release.change_set_id == command.change_set_id &&
          release.work_item_id == command.work_item_id &&
          release.attempt_id == command.attempt_id &&
          release.repository_id == attempt_state.lease_repository_id &&
          release.policy_version == attempt_state.lease_policy_version &&
          release.resources == attempt_state.lease_resources &&
          release.resource_count == attempt_state.lease_resources.length &&
          release.previous_expires_at == attempt_state.lease_expires_at &&
          release.released_at == released_at
        key(:plan).failure("must summarize the unchanged complete set and its release time") unless valid
      end
    end
  end
end
