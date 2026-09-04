# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CandidateObligationScans
      class StartPairScan
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, policy:, markers:)
          return already_decided(state, command) unless state.absent?

          reason = policy_reason(policy)
          reason ||= "no_predecessors" if command.to_revision.negative?
          reason ||= "no_routing_markers" if markers.empty?
          events = events_for(command, markers, reason)
          Success(
            EventPlan.new(
              writes: events.map do |event|
                EventWrite.new(
                  stream: @stream_factory.candidate_impact_pair_scan(command.scan_id),
                  event:
                )
              end
            )
          )
        end

        private

        def events_for(command, markers, reason)
          lifecycle = if reason
            Events::CandidateImpactPairScanSkippedV2.new(scan_id: command.scan_id, reason:)
          else
            Events::CandidateImpactPairScanStartedV2.new(
              scan_id: command.scan_id,
              change_set_id: command.change_set_id,
              direction: command.direction,
              markers:,
              from_revision: command.from_revision,
              to_revision: command.to_revision,
              page_size: command.page_size
            )
          end
          [
            lifecycle,
            source_link(command, "source_registration", command.source_registration),
            source_link(command, "policy_partition", command.policy_partition_event),
            source_link(command, "policy_head", command.policy_head.event)
          ]
        end

        def source_link(command, role, source)
          Events::CandidateImpactPairScanSourceLinkedV1.new(
            scan_id: command.scan_id,
            role:,
            source:
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
