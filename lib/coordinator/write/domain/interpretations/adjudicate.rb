# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Interpretations
      class Adjudicate
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, slot:, adjudicated_at:)
          evidence = state.proposal
          return not_found(command) unless evidence

          proposal = evidence.proposal
          return not_found(command) unless proposal.source_message_id == command.source_message_id
          return terminal_failure(state.terminal) if state.terminal
          if command.action == "accept" && state.slot_acceptance
            return occupied_slot_failure(state.slot_acceptance, slot)
          end

          event = build_event(command:, slot:)
          Success(
            EventPlan.new(
              writes: [ EventWrite.new(stream: @stream_factory.interpretation(command.interpretation_id), event:) ]
            )
          )
        end

        private

        def build_event(command:, slot:)
          common = {
            interpretation_id: command.interpretation_id,
            source_message_id: command.source_message_id
          }
          case command.action
          when "accept"
            Events::DecisionInterpretationAcceptedV2.new(
              **common,
              slot:,
              rationale: command.rationale.summary
            )
          when "reject"
            Events::DecisionInterpretationRejectedV2.new(
              **common,
              rationale: command.rationale.summary
            )
          when "request_clarification"
            clarification = command.clarification
            Events::DecisionClarificationRequiredV2.new(
              **common,
              origin: "adjudication",
              reasons: [ command.rationale.code ],
              questions: clarification.questions.map(&:prompt),
              rationale: command.rationale.summary
            )
          end
        end

        def not_found(command)
          Failure(
            OutcomeError.new(
              code: :interpretation_not_found,
              message: "Interpretation proposal does not exist for the supplied message",
              details: {
                interpretation_id: command.interpretation_id,
                message_id: command.source_message_id
              }
            )
          )
        end

        def terminal_failure(terminal)
          Failure(
            OutcomeError.new(
              code: terminal.status == "accepted" ? :interpretation_already_accepted : :interpretation_already_rejected,
              message: "Interpretation proposal already has a terminal adjudication",
              details: {
                interpretation_id: terminal.interpretation_id,
                event_id: terminal.event.event_id
              }
            )
          )
        end

        def occupied_slot_failure(acceptance, slot)
          Failure(
            OutcomeError.new(
              code: :interpretation_slot_already_accepted,
              message: "Another interpretation is already accepted in this slot",
              details: {
                interpretation_id: acceptance.interpretation_id,
                event_id: acceptance.event.event_id,
                slot_digest: slot.compound_marker.digest
              }
            )
          )
        end
      end
    end
  end
end
