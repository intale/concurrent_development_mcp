# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module AgentChoiceImpacts
      class StartScan
        include Dry::Monads[:result]

        PAGE_SIZE = 50

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, decision_change:, started_at:)
          return already_decided(state, command) unless state.absent?

          event = event_for(command, decision_change, started_at)
          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.agent_choice_impact_scan(command.scan_id),
                  event:
                )
              ]
            )
          )
        end

        private

        def event_for(command, decision_change, started_at)
          reason = skip_reason(decision_change.retroactivity)
          return skipped_event(command, decision_change, reason, started_at) if reason

          Events::AgentChoiceImpactScanStartedV1.new(
            scan_id: command.scan_id,
            decision_change:,
            from_position: 0,
            to_position: decision_change.source_global_position,
            page_size: PAGE_SIZE,
            policy_version: command.policy_version,
            started_at:
          )
        end

        def skipped_event(command, decision_change, reason, started_at)
          Events::AgentChoiceImpactScanSkippedV1.new(
            scan_id: command.scan_id,
            decision_change:,
            reason:,
            policy_version: command.policy_version,
            skipped_at: started_at
          )
        end

        def skip_reason(retroactivity)
          case retroactivity
          when "active_attempts" then nil
          when "future_only" then "future_only"
          when "all_unverified_candidates", "all_unmerged_candidates" then "candidate_scope"
          when "all_artifacts" then "artifact_scope"
          end
        end

        def already_decided(state, command)
          Failure(
            OutcomeError.new(
              code: :agent_choice_impact_scan_already_decided,
              message: "Decision change already has an AgentChoice impact scan decision",
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
