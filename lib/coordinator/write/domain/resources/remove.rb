# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Resources
      class Remove
        include Dry::Monads[:result]

        class DecisionV1 < Value
          attribute :registration, Events::ResourceIdentityV2::Registration
          attribute :current_binding, Events::ResourceIdentityV2::CurrentBinding
          attribute :unbinding, Events::ResourceIdentityV2::Unbinding.optional
          attribute :events,
                    Types::Array.of(Events::ResourceIdentityV2::Unbinding).constrained(max_size: 1)
          attribute :outcome, Types::String.enum("removed", "already_inactive", "superseded")
        end

        def call(registration:, current_binding:, reason:, removed_at:)
          return corrupt(registration, "registration_without_binding") unless current_binding

          if current_binding.resource_id != registration.resource_id
            return success(registration:, current_binding:, outcome: "superseded")
          end

          return corrupt(registration, "binding_registration_mismatch") unless
            current_binding.kind == registration.kind

          if current_binding.is_a?(Events::ResourceIdentityV2::Unbound)
            return success(
              registration:,
              current_binding:,
              outcome: "already_inactive",
            )
          end

          unbinding = Events::ResourceIdentityV2::Unbound.new(
            resource_id: registration.resource_id,
            repository_id: registration.repository_id,
            kind: registration.kind,
            normalized_path: registration.normalized_path,
            reason:
          )
          success(
            registration:,
            current_binding:,
            unbinding:,
            outcome: "removed",
          )
        end

        private

        def success(registration:, current_binding:, outcome:, unbinding: nil)
          Success(
            DecisionV1.new(
              registration:,
              current_binding:,
              unbinding:,
              events: unbinding ? [ unbinding ] : [],
              outcome:
            )
          )
        end

        def corrupt(registration, reason)
          Failure(
            OutcomeError.new(
              code: :resource_history_corrupt,
              message: "Resource identity history is inconsistent",
              details: {
                resource_id: registration.resource_id,
                repository_id: registration.repository_id,
                kind: registration.kind,
                normalized_path: registration.normalized_path,
                reason:
              }
            )
          )
        end
      end
    end
  end
end
