# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Resources
      class Remove
        include Dry::Monads[:result]

        class DecisionV1 < Value
          attribute :registration, Events::ResourceIdentityV1::Registration
          attribute :current_binding, Events::ResourceIdentityV1::CurrentBinding
          attribute :unbinding, Events::ResourceIdentityV1::Unbinding.optional
          attribute :events,
                    Types::Array.of(Events::ResourceIdentityV1::Unbinding).constrained(max_size: 1)
          attribute :outcome, Types::String.enum("removed", "already_inactive", "superseded")
          attribute :unbound_at, Types::Timestamp.optional
        end

        def call(registration:, current_binding:, reason:, removed_at:)
          return corrupt(registration, "registration_without_binding") unless current_binding

          if current_binding.resource_id != registration.resource_id
            return success(registration:, current_binding:, outcome: "superseded")
          end

          return corrupt(registration, "binding_registration_mismatch") unless
            current_binding.kind == registration.kind

          if current_binding.is_a?(Events::ResourceIdentityV1::Unbound)
            return success(
              registration:,
              current_binding:,
              outcome: "already_inactive",
              unbound_at: current_binding.unbound_at
            )
          end

          unbinding = Events::ResourceIdentityV1::Unbound.new(
            resource_id: registration.resource_id,
            repository_id: registration.repository_id,
            kind: registration.kind,
            normalized_path: registration.normalized_path,
            reason:,
            unbound_at: removed_at
          )
          success(
            registration:,
            current_binding:,
            unbinding:,
            outcome: "removed",
            unbound_at: removed_at
          )
        end

        private

        def success(registration:, current_binding:, outcome:, unbinding: nil, unbound_at: nil)
          Success(
            DecisionV1.new(
              registration:,
              current_binding:,
              unbinding:,
              events: unbinding ? [ unbinding ] : [],
              outcome:,
              unbound_at:
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
