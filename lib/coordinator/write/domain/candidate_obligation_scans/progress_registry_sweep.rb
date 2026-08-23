# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CandidateObligationScans
      class ProgressRegistrySweep
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, progressed_at:)
          denial = denied(state, command)
          return denial if denial

          next_revision = command.last_processed_revision ? command.last_processed_revision + 1 : command.previous_from_revision
          event = if command.has_more
            progressed_event(state, command, next_revision, progressed_at)
          else
            completed_event(state, command, next_revision, progressed_at)
          end
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

        def denied(state, command)
          return failure(:candidate_impact_registry_sweep_not_running, state, command) unless state.running?
          unless matching_scan?(state, command)
            return failure(:candidate_impact_registry_sweep_mismatch, state, command)
          end
          unless state.checkpoint_event == command.expected_checkpoint &&
                 state.from_revision == command.previous_from_revision
            return failure(:candidate_impact_registry_sweep_checkpoint_changed, state, command)
          end
          return failure(:candidate_impact_registry_sweep_page_invalid, state, command) unless valid_page?(state, command)

          nil
        end

        def matching_scan?(state, command)
          state.scan_id == command.scan_id &&
            state.change_set_id == command.change_set_id &&
            state.policy_partition_event == command.policy_partition_event &&
            state.policy_head == command.policy_head &&
            state.page_size == command.page_size &&
            state.rule_version == command.rule_version
        end

        def valid_page?(state, command)
          last = command.last_processed_revision
          return false if command.has_more && !last
          return command.page_registration_count.zero? unless last

          last >= command.previous_from_revision &&
            last <= state.to_revision &&
            (!command.has_more || last < state.to_revision)
        end

        def progressed_event(state, command, next_revision, progressed_at)
          Events::CandidateImpactRegistrySweepProgressedV1.new(
            **common(state, command),
            previous_from_revision: command.previous_from_revision,
            next_from_revision: next_revision,
            page_number: state.page_count + 1,
            page_registration_count: command.page_registration_count,
            total_registration_count: state.total_registration_count + command.page_registration_count,
            progressed_at:
          )
        end

        def completed_event(state, command, next_revision, progressed_at)
          Events::CandidateImpactRegistrySweepCompletedV1.new(
            **common(state, command),
            previous_from_revision: command.previous_from_revision,
            final_from_revision: next_revision,
            page_count: state.page_count + 1,
            page_registration_count: command.page_registration_count,
            total_registration_count: state.total_registration_count + command.page_registration_count,
            completed_at: progressed_at
          )
        end

        def common(state, command)
          {
            scan_id: command.scan_id,
            change_set_id: command.change_set_id,
            policy_partition_event: command.policy_partition_event,
            policy_head: command.policy_head,
            started_event: state.started_event,
            previous_checkpoint: state.checkpoint_event,
            to_revision: state.to_revision,
            page_size: command.page_size,
            rule_version: command.rule_version
          }
        end

        def failure(code, state, command)
          Failure(
            OutcomeError.new(
              code:,
              message: "Candidate impact registry sweep cannot advance from the supplied checkpoint",
              details: {
                scan_id: command.scan_id,
                status: state.status,
                expected_checkpoint: command.expected_checkpoint.to_h,
                current_checkpoint: state.checkpoint_event&.to_h,
                requested_from_revision: command.previous_from_revision,
                current_from_revision: state.from_revision,
                to_revision: state.to_revision
              }
            )
          )
        end
      end
    end
  end
end
