# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationValidityScans
      class Start
        include Dry::Monads[:result]

        PAGE_SIZE = 50

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          return already_decided(state, command) unless state.absent?

          events = [
            Events::VerificationObligationValidityScanStartedV2.new(
              scan_id: command.scan_id,
              change_set_id: command.change_set_id,
              from_position: 0,
              to_position: command.source_global_position,
              page_size: PAGE_SIZE
            ),
            Events::VerificationObligationValidityScanSourceLinkedV1.new(
              scan_id: command.scan_id,
              role: "superseding_partition",
              source: command.superseding_partition_event
            )
          ]
          Success(
            EventPlan.new(
              writes: events.map do |event|
                EventWrite.new(
                  stream: @stream_factory.verification_obligation_validity_scan(command.scan_id),
                  event:
                )
              end
            )
          )
        end

        private

        def already_decided(state, command)
          Failure(
            OutcomeError.new(
              code: :verification_obligation_validity_scan_already_decided,
              message: "Policy partition already has a validity scan decision",
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
