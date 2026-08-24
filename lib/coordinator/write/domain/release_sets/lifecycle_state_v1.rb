# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class LifecycleStateV1 < Value
        Integration = Coordinator::Write::ReleaseSets::IntegrationFactV1
        Verification = Coordinator::Write::ReleaseSets::VerificationFactV1

        attribute :preparation, Coordinator::Write::ReleaseSets::PreparationFactV1.optional
        attribute :integrations,
                  Types::Array.of(Integration)
                    .constrained(
                      max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS *
                        Types::RELEASE_SET_INTEGRATION_MAXIMUM_ATTEMPTS
                    )
        attribute :verifications,
                  Types::Array.of(Verification)
                    .constrained(max_size: Types::RELEASE_SET_VERIFICATION_MAXIMUM_ATTEMPTS)

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
          latest_integration(repository_id)&.payload&.outcome == "integrated"
        end

        def all_integrated?
          preparation && preparation.payload.ordered_members.all? { integrated?(_1.repository_id) }
        end

        def successful_integrations
          return [] unless preparation

          preparation.payload.ordered_members.filter_map do |member|
            integration = latest_integration(member.repository_id)
            integration if integration&.payload&.outcome == "integrated"
          end.freeze
        end

        def latest_verification
          verifications.last
        end

        def verified?
          latest_verification&.payload&.evidence&.outcome == "passed"
        end
      end
    end
  end
end
