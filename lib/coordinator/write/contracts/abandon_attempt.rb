# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AbandonAttempt < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:change_set_id).filled(:string)
        required(:work_item_id).filled(:string)
        required(:attempt_id).filled(:string)
        required(:reason).filled(
          :string,
          max_size?: 2_000
        )
      end

      rule(:command_id, :change_set_id, :work_item_id, :attempt_id) do
        %i[command_id change_set_id work_item_id attempt_id].each do |name|
          identifier = values[name]
          next unless identifier.is_a?(String)
          next if Types::IDENTIFIER_PATTERN.match?(identifier)

          key(name).failure("must be a valid identifier")
        end
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end
    end

    class AttemptAbandonmentEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::AbandonAttempt))
        required(:attempt_state).value(Types.Instance(Domain::Attempts::State))
        required(:abandoned_at).filled(:string)
      end

      rule(:plan, :command, :attempt_state, :abandoned_at) do
        plan = values[:plan]
        command = values[:command]
        attempt_state = values[:attempt_state]
        unless plan.writes.length.between?(2, 34)
          key(:plan).failure("must contain between 2 and 34 ordered writes")
          next
        end

        abandonment = plan.events[-2]
        requeue = plan.events[-1]
        releases = plan.events.first(plan.events.length - 2)
        expected_streams = releases.map do |event|
          StreamFactory.new.resource_lease(lease_identity(event))
        end + [
          StreamFactory.new.attempt(command.attempt_id),
          StreamFactory.new.work_item(command.work_item_id)
        ]

        release_class = v2?(attempt_state) ? Events::ResourceLeaseReleasedV2 : Events::ResourceLeaseReleasedV1
        abandonment_class = v2?(attempt_state) ? Events::AttemptAbandonedV2 : Events::AttemptAbandonedV1
        unless plan.writes.map(&:stream) == expected_streams &&
               releases.all? { _1.is_a?(release_class) } &&
               abandonment.is_a?(abandonment_class) &&
               requeue.is_a?(Events::WorkItemRequeuedV1)
          key(:plan).failure("must release zero or more resources before one Attempt abandonment and WorkItem requeue")
          next
        end

        scope = [ command.change_set_id, command.work_item_id, command.attempt_id ]
        terminal_scope = [ abandonment, requeue ].map do |event|
          [ event.change_set_id, event.work_item_id, event.attempt_id ]
        end
        unless terminal_scope.uniq == [ scope ] &&
               abandonment.agent_id == command.actor.id &&
               requeue.agent_id == command.actor.id &&
               abandonment.reason == command.reason &&
               requeue.reason == command.reason &&
               abandonment.abandoned_at == values[:abandoned_at] &&
               requeue.requeued_at == values[:abandoned_at]
          key(:plan).failure("must preserve the accepted scope, actor, reason, and timestamp")
        end

        released_identities = abandonment.released_leases.map { lease_identity(_1) }
        untouched_identities = if abandonment.respond_to?(:untouched_resource_ids)
                                 abandonment.untouched_resource_ids
                               else
                                 abandonment.untouched_resource_key_hashes
                               end
        expected_identities = attempt_state.lease_resources.map { lease_identity(_1) }.sort
        unless abandonment.lease_set_id == attempt_state.lease_set_id &&
               releases.map { lease_identity(_1) } == released_identities &&
               (released_identities + untouched_identities).sort == expected_identities &&
               (released_identities & untouched_identities).empty?
          key(:plan).failure("must partition the recorded write set into released and untouched fences")
        end
      end

      private

      def v2?(attempt_state)
        attempt_state.lease_policy_version == LeaseResourceV2::POLICY_VERSION
      end

      def lease_identity(value)
        return value.resource_id if value.respond_to?(:resource_id)

        value.resource_key_hash
      end
    end
  end
end
