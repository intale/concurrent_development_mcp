# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CandidateObligationScans
      class StartPairScan
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, policy:, markers:, started_at:)
          return already_decided(state, command) unless state.absent?

          reason = policy_reason(policy)
          reason ||= "no_predecessors" if command.to_revision.negative?
          reason ||= "no_routing_markers" if markers.empty?
          event = reason ? skipped_event(command, markers, reason, started_at) : started_event(command, markers, started_at)
          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.candidate_impact_pair_scan(command.scan_id),
                  event:
                )
              ]
            )
          )
        end

        private

        def started_event(command, markers, started_at)
          Events::CandidateImpactPairScanStartedV1.new(
            **common(command, markers),
            to_revision: command.to_revision,
            started_at:
          )
        end

        def skipped_event(command, markers, reason, started_at)
          Events::CandidateImpactPairScanSkippedV1.new(
            **common(command, markers),
            to_revision: command.to_revision,
            reason:,
            skipped_at: started_at
          )
        end

        def common(command, markers)
          {
            scan_id: command.scan_id,
            change_set_id: command.change_set_id,
            source_registration: command.source_registration,
            direction: command.direction,
            policy_partition_event: command.policy_partition_event,
            policy_head: command.policy_head,
            markers:,
            from_revision: command.from_revision,
            page_size: command.page_size,
            index_policy_version: command.index_policy_version,
            rule_version: command.rule_version
          }
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
              code: :candidate_impact_pair_scan_already_decided,
              message: "Candidate impact pair scan already has a start decision",
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
