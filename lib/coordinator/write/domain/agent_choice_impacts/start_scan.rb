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

        def call(state:, command:, decision_change:)
          return already_decided(state, command) unless state.absent?

          events = events_for(command, decision_change)
          Success(
            EventPlan.new(
              writes: events.map do |event|
                EventWrite.new(
                  stream: @stream_factory.agent_choice_impact_scan(command.scan_id),
                  event:
                )
              end
            )
          )
        end

        private

        def events_for(command, decision_change)
          reason = skip_reason(decision_change.retroactivity)
          lifecycle = if reason
            Events::AgentChoiceImpactScanSkippedV2.new(scan_id: command.scan_id, reason:)
          else
            Events::AgentChoiceImpactScanStartedV2.new(
              scan_id: command.scan_id,
              decision_change:,
              from_position: 0,
              to_position: decision_change.source_global_position,
              page_size: PAGE_SIZE
            )
          end
          [
            lifecycle,
            Events::AgentChoiceImpactScanSourceLinkedV1.new(
              scan_id: command.scan_id,
              role: "decision_change",
              source: decision_change.source_event
            )
          ]
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
