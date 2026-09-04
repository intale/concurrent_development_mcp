# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CandidateObligationScans
      class StartRegistrySweep
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, policy:, latest_registry_revision:)
          return already_decided(state, command) unless state.absent?

          events = events_for(command, policy, latest_registry_revision)
          Success(
            EventPlan.new(
              writes: events.map do |event|
                EventWrite.new(
                  stream: @stream_factory.candidate_impact_registry_sweep(command.scan_id),
                  event:
                )
              end
            )
          )
        end

        private

        def events_for(command, policy, latest_revision)
          reason = policy_reason(policy) || ("empty_registry" unless latest_revision)
          lifecycle = if reason
            Events::CandidateImpactRegistrySweepSkippedV2.new(scan_id: command.scan_id, reason:)
          else
            Events::CandidateImpactRegistrySweepStartedV2.new(
              scan_id: command.scan_id,
              change_set_id: command.change_set_id,
              from_revision: command.from_revision,
              to_revision: latest_revision,
              page_size: command.page_size
            )
          end
          [
            lifecycle,
            source_link(command, "policy_partition", command.policy_partition_event),
            source_link(command, "policy_head", command.policy_head.event)
          ]
        end

        def source_link(command, role, source)
          Events::CandidateImpactRegistrySweepSourceLinkedV1.new(
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
