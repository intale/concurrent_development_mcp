# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class CompleteActivated
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new,
          digest_builder: Coordinator::Write::ReleaseSets::CompletionDigestBuilder.new
        )
          @stream_factory = stream_factory
          @digest_builder = digest_builder
        end

        def call(state:, command:, completed_at:)
          denial = denied(state:, command:)
          return denial if denial

          preparation = state.preparation.payload
          attributes = {
            release_set_id: command.release_set_id,
            release_digest: preparation.release_digest,
            outcome: "activated",
            source_event: command.activation_event,
            compensation_evidence: [],
            rule_version: command.rule_version
          }
          event = Events::ReleaseSetCompletedV1.new(
            **attributes,
            change_set_id: preparation.change_set_id,
            completion_digest: @digest_builder.call(**attributes),
            completed_at:
          )
          Success(EventPlan.new(writes: [ EventWrite.new(stream: @stream_factory.release_set(command.release_set_id), event:) ]))
        end

        private

        def denied(state:, command:)
          return failure(:release_set_not_found, "ReleaseSet has not been prepared") unless state.preparation
          return failure(:release_set_already_completed, "ReleaseSet is already completed") if state.completed?
          return failure(:release_set_not_activated, "ReleaseSet has not been activated") unless state.activation
          return failure(:release_activation_binding_stale, "Completion does not bind the exact activation") unless command.activation_event == state.activation.event

          nil
        end

        def failure(code, message)
          Failure(OutcomeError.new(code:, message:, details: {}))
        end
      end
    end
  end
end
