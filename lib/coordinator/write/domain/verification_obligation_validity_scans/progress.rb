# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationValidityScans
      class Progress
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, progressed_at:)
          denial = denied(state, command)
          return denial if denial

          next_position = command.last_processed_position ?
            command.last_processed_position + 1 : command.previous_from_position
          event = command.has_more ?
            progressed_event(state, command, next_position, progressed_at) :
            completed_event(state, command, next_position, progressed_at)
          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.verification_obligation_validity_scan(command.scan_id),
                  event:
                )
              ]
            )
          )
        end

        private

        def denied(state, command)
          return failure(:verification_obligation_validity_scan_not_running, state, command) unless state.running?
          return failure(:verification_obligation_validity_scan_mismatch, state, command) unless matching_scan?(state, command)
          unless state.checkpoint_event == command.expected_checkpoint &&
                 state.from_position == command.previous_from_position
            return failure(:verification_obligation_validity_scan_checkpoint_changed, state, command)
          end
          return failure(:verification_obligation_validity_scan_page_invalid, state, command) unless valid_page?(state, command)

          nil
        end

        def matching_scan?(state, command)
          state.scan_id == command.scan_id &&
            state.change_set_id == command.change_set_id &&
            state.superseding_partition_event == command.superseding_partition_event &&
            state.page_size == command.page_size &&
            state.rule_version == command.rule_version
        end

        def valid_page?(state, command)
          last = command.last_processed_position
          return command.page_obligation_count.zero? && !command.has_more unless last

          last >= command.previous_from_position &&
            last <= state.to_position &&
            (!command.has_more || last < state.to_position) &&
            command.page_obligation_count.positive? &&
            (!command.has_more || command.page_obligation_count == command.page_size)
        end

        def progressed_event(state, command, next_position, progressed_at)
          Events::VerificationObligationValidityScanProgressedV1.new(
            **common(state, command),
            previous_from_position: command.previous_from_position,
            next_from_position: next_position,
            page_number: state.page_count + 1,
            page_obligation_count: command.page_obligation_count,
            total_obligation_count: state.total_obligation_count + command.page_obligation_count,
            progressed_at:
          )
        end

        def completed_event(state, command, next_position, progressed_at)
          Events::VerificationObligationValidityScanCompletedV1.new(
            **common(state, command),
            previous_from_position: command.previous_from_position,
            final_from_position: next_position,
            page_count: state.page_count + 1,
            page_obligation_count: command.page_obligation_count,
            total_obligation_count: state.total_obligation_count + command.page_obligation_count,
            completed_at: progressed_at
          )
        end

        def common(state, command)
          {
            scan_id: command.scan_id,
            change_set_id: command.change_set_id,
            superseding_partition_event: command.superseding_partition_event,
            started_event: state.started_event,
            previous_checkpoint: state.checkpoint_event,
            page_size: command.page_size,
            rule_version: command.rule_version
          }
        end

        def failure(code, state, command)
          Failure(
            OutcomeError.new(
              code:,
              message: "Verification-obligation validity scan cannot advance from the supplied checkpoint",
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
