# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CandidateObligationScans
      class ProgressPairScan
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          denial = denied(state, command)
          return denial if denial

          next_revision = command.last_processed_revision ? command.last_processed_revision + 1 : command.previous_from_revision
          event = if command.has_more
            progressed_event(state, command, next_revision)
          else
            completed_event(command)
          end
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

        def denied(state, command)
          return failure(:candidate_impact_pair_scan_not_running, state, command) unless state.running?
          unless matching_scan?(state, command)
            return failure(:candidate_impact_pair_scan_mismatch, state, command)
          end
          unless state.checkpoint_event == command.expected_checkpoint &&
                 state.from_revision == command.previous_from_revision
            return failure(:candidate_impact_pair_scan_checkpoint_changed, state, command)
          end
          return failure(:candidate_impact_pair_scan_page_invalid, state, command) unless valid_page?(state, command)

          nil
        end

        def matching_scan?(state, command)
          state.scan_id == command.scan_id &&
            state.change_set_id == command.change_set_id &&
            state.source_registration == command.source_registration &&
            state.direction == command.direction &&
            state.policy_partition_event == command.policy_partition_event &&
            state.policy_head == command.policy_head &&
            state.page_size == command.page_size &&
            state.index_policy_version == command.index_policy_version &&
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

        def progressed_event(state, command, next_revision)
          Events::CandidateImpactPairScanProgressedV2.new(
            scan_id: command.scan_id,
            page_number: state.page_count + 1,
            next_from_revision: next_revision,
            change_set_id: state.change_set_id,
            direction: state.direction,
            markers: state.markers,
            to_revision: state.to_revision,
            page_size: state.page_size
          )
        end

        def completed_event(command)
          Events::CandidateImpactPairScanCompletedV2.new(scan_id: command.scan_id)
        end

        def failure(code, state, command)
          Failure(
            OutcomeError.new(
              code:,
              message: "Candidate impact pair scan cannot advance from the supplied checkpoint",
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
