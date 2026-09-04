# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class RequestCompensation
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          trigger = trigger_for(state, command.trigger_event)
          denial = denied(state:, trigger:)
          return denial if denial

          preparation = state.preparation.payload
          stream = @stream_factory.release_set(command.release_set_id)
          writes = [
            EventWrite.new(
              stream:,
              event: Events::ReleaseSetCompensationRequestedV2.new(
                release_set_id: command.release_set_id,
                change_set_id: preparation.change_set_id,
                reason: reason(trigger),
                trigger_kind: trigger_kind(trigger)
              )
            )
          ]
          state.successful_integrations.each do |integration|
            writes << EventWrite.new(
              stream:,
              event: Events::ReleaseSetSuccessfulIntegrationLinkedV1.new(
                release_set_id: command.release_set_id,
                integration_event: integration.event
              )
            )
          end
          Success(EventPlan.new(writes:))
        end

        private

        def trigger_for(state, reference)
          state.integrations.find { _1.event == reference } || state.verifications.find { _1.event == reference }
        end

        def denied(state:, trigger:)
          return failure(:release_set_not_found, "ReleaseSet has not been prepared") unless state.preparation
          return failure(:release_set_already_completed, "ReleaseSet is already completed") if state.completed?
          return failure(:release_set_already_activated, "Activated ReleaseSet cannot request compensation") if state.activated?
          return failure(:release_set_compensation_already_requested, "ReleaseSet compensation is already requested") if state.compensation_requested?
          return failure(:release_compensation_trigger_not_found, "Compensation trigger is not in ReleaseSet history") unless trigger
          return failure(:release_compensation_not_required, "ReleaseSet has no successful integration to compensate") if state.successful_integrations.empty?

          return nil if compensation_trigger?(trigger)

          failure(:release_compensation_trigger_invalid, "Trigger is not a failed integration or verification")
        end

        def compensation_trigger?(trigger)
          case trigger
          when Coordinator::Write::ReleaseSets::IntegrationFactV2
            trigger.payload.outcome == "failed"
          when Coordinator::Write::ReleaseSets::VerificationFactV2
            trigger.payload.evidence.outcome == "failed"
          else
            false
          end
        end

        def trigger_kind(trigger)
          return "repository_integration_failed" if trigger.is_a?(Coordinator::Write::ReleaseSets::IntegrationFactV2)

          "release_verification_failed"
        end

        def reason(trigger)
          return trigger.payload.failure.summary if trigger.is_a?(Coordinator::Write::ReleaseSets::IntegrationFactV2)

          "Composite ReleaseSet verification failed"
        end

        def failure(code, message)
          Failure(OutcomeError.new(code:, message:, details: {}))
        end
      end
    end
  end
end
