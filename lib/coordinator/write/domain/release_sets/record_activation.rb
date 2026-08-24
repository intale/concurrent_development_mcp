# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class RecordActivation
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new,
          digest_builder: Coordinator::Write::ReleaseSets::ActivationDigestBuilder.new
        )
          @stream_factory = stream_factory
          @digest_builder = digest_builder
        end

        def call(state:, command:, recorded_at:)
          denial = denied(state:, command:)
          return denial if denial

          preparation = state.preparation.payload
          verification = state.latest_verification
          attributes = {
            release_set_id: command.release_set_id,
            release_digest: preparation.release_digest,
            verification_event: command.verification_event,
            verification_digest: command.verification_digest,
            activation_point: command.activation_point,
            policy_version: command.policy_version
          }
          event = Events::ReleaseSetActivatedV1.new(
            **attributes,
            change_set_id: preparation.change_set_id,
            activation_digest: @digest_builder.call(**attributes),
            evidence_status: "attributed_unverified",
            recorded_at:
          )
          Success(EventPlan.new(writes: [ EventWrite.new(stream: @stream_factory.release_set(command.release_set_id), event:) ]))
        end

        private

        def denied(state:, command:)
          return failure(:release_set_not_found, "ReleaseSet has not been prepared") unless state.preparation
          return failure(:release_set_already_completed, "ReleaseSet is already completed") if state.completed?
          return failure(:release_set_compensation_requested, "ReleaseSet compensation has been requested") if state.compensation_requested?
          return failure(:release_set_already_activated, "ReleaseSet is already activated") if state.activated?
          return failure(:release_set_integrations_incomplete, "Every ReleaseSet member must be integrated") unless state.all_integrated?
          return failure(:release_set_not_verified, "Latest ReleaseSet verification must pass") unless state.verified?

          verification = state.latest_verification
          unless command.verification_event == verification.event &&
                 command.verification_digest == verification.payload.verification_digest
            return failure(:release_activation_verification_binding_stale, "Activation does not bind the exact latest passing verification")
          end

          nil
        end

        def failure(code, message)
          Failure(OutcomeError.new(code:, message:, details: {}))
        end
      end
    end
  end
end
