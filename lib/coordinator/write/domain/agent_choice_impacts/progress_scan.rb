# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module AgentChoiceImpacts
      class ProgressScan
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, progressed_at:)
          denial = denied(state, command)
          return denial if denial

          next_position = command.last_processed_position ? command.last_processed_position + 1 : command.previous_from_position
          event =
            if command.has_more
              progressed_event(state, command, next_position, progressed_at)
            else
              completed_event(state, command, next_position, progressed_at)
            end
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

        def denied(state, command)
          return failure(:agent_choice_impact_scan_not_running, state, command) unless state.running?
          unless state.scan_id == command.scan_id && state.policy_version == command.policy_version
            return failure(:agent_choice_impact_scan_mismatch, state, command)
          end
          unless state.checkpoint_event == command.expected_checkpoint &&
                 state.from_position == command.previous_from_position
            return failure(:agent_choice_impact_scan_checkpoint_changed, state, command)
          end
          if command.last_processed_position &&
             (command.last_processed_position > state.to_position ||
              command.has_more && command.last_processed_position == state.to_position)
            return failure(:agent_choice_impact_scan_page_out_of_bounds, state, command)
          end

          nil
        end

        def progressed_event(state, command, next_position, progressed_at)
          Events::AgentChoiceImpactScanProgressedV1.new(
            scan_id: command.scan_id,
            started_event: state.started_event,
            previous_checkpoint: state.checkpoint_event,
            previous_from_position: command.previous_from_position,
            next_from_position: next_position,
            page_number: state.page_count + 1,
            page_choice_count: command.page_choice_count,
            total_choice_count: state.total_choice_count + command.page_choice_count,
            policy_version: command.policy_version,
            progressed_at:
          )
        end

        def completed_event(state, command, next_position, progressed_at)
          Events::AgentChoiceImpactScanCompletedV1.new(
            scan_id: command.scan_id,
            started_event: state.started_event,
            previous_checkpoint: state.checkpoint_event,
            previous_from_position: command.previous_from_position,
            final_from_position: next_position,
            page_count: state.page_count + 1,
            page_choice_count: command.page_choice_count,
            total_choice_count: state.total_choice_count + command.page_choice_count,
            policy_version: command.policy_version,
            completed_at: progressed_at
          )
        end

        def failure(code, state, command)
          Failure(
            OutcomeError.new(
              code:,
              message: "AgentChoice impact scan cannot advance from the supplied checkpoint",
              details: {
                scan_id: command.scan_id,
                status: state.status,
                expected_checkpoint: command.expected_checkpoint.to_h,
                current_checkpoint: state.checkpoint_event&.to_h,
                requested_from_position: command.previous_from_position,
                current_from_position: state.from_position,
                to_position: state.to_position
              }
            )
          )
        end
      end
    end
  end
end
