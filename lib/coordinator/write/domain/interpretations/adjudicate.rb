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

          event = build_event(command:, evidence:, slot:, adjudicated_at:)
          Success(
            EventPlan.new(
              writes: [ EventWrite.new(stream: @stream_factory.interpretation(command.source_message_id), event:) ]
            )
          )
        end

        private

        def build_event(command:, evidence:, slot:, adjudicated_at:)
          common = {
            interpretation_id: command.interpretation_id,
            source_message_id: command.source_message_id
          }
          case command.action
          when "accept"
            Events::DecisionInterpretationAcceptedV1.new(
              **common,
              proposal_event: evidence.event,
              slot:,
              rationale: command.rationale,
              accepted_at: adjudicated_at
            )
          when "reject"
            Events::DecisionInterpretationRejectedV1.new(
              **common,
              proposal_event: evidence.event,
              rationale: command.rationale,
              rejected_at: adjudicated_at
            )
          when "request_clarification"
            clarification = command.clarification
            Events::DecisionClarificationRequiredV1.new(
              **common,
              status: clarification.status,
              origin: "adjudication",
              reasons: [ command.rationale.code ],
              questions: clarification.questions,
              rationale: command.rationale,
              required_at: adjudicated_at
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
