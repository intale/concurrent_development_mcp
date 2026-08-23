# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CandidateObligationScans
      class StartRegistrySweep
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, policy:, latest_registry_revision:, started_at:)
          return already_decided(state, command) unless state.absent?

          event = event_for(command, policy, latest_registry_revision, started_at)
          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.candidate_impact_registry_sweep(command.scan_id),
                  event:
                )
              ]
            )
          )
        end

        private

        def event_for(command, policy, latest_revision, started_at)
          reason = policy_reason(policy) || ("empty_registry" unless latest_revision)
          return skipped_event(command, reason, latest_revision, started_at) if reason

          Events::CandidateImpactRegistrySweepStartedV1.new(
            scan_id: command.scan_id,
            change_set_id: command.change_set_id,
            policy_partition_event: command.policy_partition_event,
            policy_head: command.policy_head,
            from_revision: command.from_revision,
            to_revision: latest_revision,
            page_size: command.page_size,
            rule_version: command.rule_version,
            started_at:
          )
        end

        def skipped_event(command, reason, latest_revision, started_at)
          Events::CandidateImpactRegistrySweepSkippedV1.new(
            scan_id: command.scan_id,
            change_set_id: command.change_set_id,
            policy_partition_event: command.policy_partition_event,
            policy_head: command.policy_head,
            from_revision: command.from_revision,
            to_revision: latest_revision || -1,
            page_size: command.page_size,
            reason:,
            rule_version: command.rule_version,
            skipped_at: started_at
          )
        end

        def policy_reason(policy)
          {
            "stale" => "stale_policy",
            "non_gating" => "non_gating_policy",
            "inactive" => "inactive_policy"
          }[policy.status]
        end

        def already_decided(state, command)
          Failure(
            OutcomeError.new(
              code: :candidate_impact_registry_sweep_already_decided,
              message: "Candidate impact registry sweep already has a start decision",
              details: {
                scan_id: command.scan_id,
                status: state.status,
                checkpoint_event: state.checkpoint_event&.to_h
              }
            )
          )
        end
      end
    end
  end
end
