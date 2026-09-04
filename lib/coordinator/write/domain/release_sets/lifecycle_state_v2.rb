# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class LifecycleStateV2 < Value
        Integration = Coordinator::Write::ReleaseSets::IntegrationFactV2
        Verification = Coordinator::Write::ReleaseSets::VerificationFactV2
        Activation = Coordinator::Write::ReleaseSets::ActivationFactV2
        CompensationRequest = Coordinator::Write::ReleaseSets::CompensationRequestFactV2
        Completion = Coordinator::Write::ReleaseSets::CompletionFactV2

        attribute :preparation, Coordinator::Write::ReleaseSets::PreparationFactV2.optional
        attribute :integrations,
                  Types::Array.of(Integration)
                    .constrained(
                      max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS *
                        Types::RELEASE_SET_INTEGRATION_MAXIMUM_ATTEMPTS
                    )
        attribute :verifications,
                  Types::Array.of(Verification)
                    .constrained(max_size: Types::RELEASE_SET_VERIFICATION_MAXIMUM_ATTEMPTS)
        attribute? :activation, Activation.optional
        attribute? :compensation_request, CompensationRequest.optional
        attribute? :completion, Completion.optional

        def member(repository_id)
          preparation&.payload&.ordered_members&.find { _1.repository_id == repository_id }
        end

        def integrations_for(repository_id)
          integrations.select { _1.payload.repository_id == repository_id }
        end

        def latest_integration(repository_id)
          integrations_for(repository_id).last
        end

        def integrated?(repository_id)
          integration = latest_integration(repository_id)
          integration&.payload&.outcome == "integrated" && !integration.merge_observation.nil?
        end

        def all_integrated?
          preparation && preparation.payload.ordered_members.all? { integrated?(_1.repository_id) }
        end

        def successful_integrations
          return [] unless preparation

          preparation.payload.ordered_members.filter_map do |member|
            integration = latest_integration(member.repository_id)
            integration if integration&.payload&.outcome == "integrated" && integration.merge_observation
          end.freeze
        end

        def latest_verification
          verifications.last
        end

        def verified?
          verification = latest_verification
          verification&.payload&.evidence&.outcome == "passed" &&
            verification.integration_events == successful_integrations.map(&:event)
        end

        def activated?
          !activation.nil?
        end

        def compensation_requested?
          !compensation_request.nil?
        end

        def completed?
          !completion.nil?
        end
      end
    end
  end
end
