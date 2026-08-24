# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class RecordVerification
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new,
          digest_builder: Coordinator::Write::ReleaseSets::VerificationDigestBuilder.new
        )
          @stream_factory = stream_factory
          @digest_builder = digest_builder
        end

        def call(state:, command:, recorded_at:)
          denial = denied(state:, command:)
          return denial if denial

          preparation = state.preparation.payload
          attempt_number = state.verifications.length + 1
          attributes = {
            release_set_id: command.release_set_id,
            release_digest: preparation.release_digest,
            attempt_number:,
            integration_events: command.integration_events,
            evidence: command.evidence,
            policy_version: command.policy_version
          }
          event = Events::ReleaseSetVerificationRecordedV1.new(
            **attributes,
            change_set_id: preparation.change_set_id,
            verification_digest: @digest_builder.call(**attributes),
            evidence_status: "attributed_unverified",
            recorded_at:
          )
          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.release_set(command.release_set_id),
                  event:
                )
              ]
            )
          )
        end

        private

        def denied(state:, command:)
          return failure(:release_set_not_found, "ReleaseSet has not been prepared") unless state.preparation
          return failure(:release_set_integrations_incomplete, "Every ReleaseSet member must be integrated") unless state.all_integrated?
          return failure(:release_set_already_verified, "ReleaseSet already has a passing composite verification") if state.verified?
          if state.verifications.length >= Types::RELEASE_SET_VERIFICATION_MAXIMUM_ATTEMPTS
            return failure(:release_verification_attempt_limit_reached, "ReleaseSet verification attempt limit was reached")
          end
          unless command.integration_events == state.successful_integrations.map(&:event)
            return failure(:release_verification_integration_binding_stale, "Integration references are not the exact current successful set")
          end
          if command.evidence.outcome == "passed" && command.evidence.findings.any? { %w[error critical].include?(_1.severity) }
            return failure(:release_verification_evidence_invalid, "Passing verification cannot contain error or critical findings")
          end

          nil
        end

        def failure(code, message, details = {})
          Failure(OutcomeError.new(code:, message:, details:))
        end
      end
    end
  end
end
