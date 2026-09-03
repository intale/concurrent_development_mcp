# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Resources
      class Resolve
        include Dry::Monads[:result]

        class DecisionV1 < Value
          attribute :registration, Events::ResourceIdentityV2::Registration
          attribute :binding, Events::ResourceIdentityV2::Binding
          attribute :events,
                    Types::Array.of(Events::ResourceIdentityV2::ResolutionEvent).constrained(max_size: 2)
          attribute :outcome, Types::String.enum("registered", "reactivated", "existing")
        end

        def call(identity:, proposed_resource_id:, registration:, current_binding:)
          return resolve_registered(identity:, registration:, current_binding:) if registration
          if current_binding.is_a?(Events::ResourceIdentityV2::Bound)
            return resolve_occupied(identity:, current_binding:)
          end

          register(identity:, resource_id: proposed_resource_id)
        end

        private

        def resolve_registered(identity:, registration:, current_binding:)
          return corrupt(identity, "registration_without_binding") unless current_binding

          if current_binding.is_a?(Events::ResourceIdentityV2::Bound) &&
             current_binding.resource_id == registration.resource_id
            return corrupt(identity, "binding_registration_mismatch") unless
              current_binding.kind == registration.kind

            return Success(
              DecisionV1.new(
                registration:,
                binding: current_binding,
                events: [],
                outcome: "existing"
              )
            )
          end

          if current_binding.is_a?(Events::ResourceIdentityV2::Unbound)
            if current_binding.resource_id == registration.resource_id &&
               current_binding.kind != registration.kind
              return corrupt(identity, "binding_registration_mismatch")
            end

            return reactivate(identity:, registration:)
          end

          return path_conflict(identity, current_binding) unless current_binding.kind == identity.kind

          corrupt(identity, "binding_registration_mismatch")
        end

        def resolve_occupied(identity:, current_binding:)
          return path_conflict(identity, current_binding) unless
            current_binding.kind == identity.kind

          corrupt(identity, "binding_without_registration")
        end

        def reactivate(identity:, registration:)
          binding = Events::ResourceIdentityV2::Bound.new(
            resource_id: registration.resource_id,
            repository_id: identity.repository_id,
            kind: identity.kind,
            normalized_path: identity.normalized_path
          )

          Success(
            DecisionV1.new(
              registration:,
              binding:,
              events: [ binding ],
              outcome: "reactivated"
            )
          )
        end

        def register(identity:, resource_id:)
          registration = Events::ResourceIdentityV2::Registered.new(
            resource_id:,
            repository_id: identity.repository_id,
            kind: identity.kind,
            normalized_path: identity.normalized_path
          )
          binding = Events::ResourceIdentityV2::Bound.new(
            resource_id:,
            repository_id: identity.repository_id,
            kind: identity.kind,
            normalized_path: identity.normalized_path
          )

          Success(
            DecisionV1.new(
              registration:,
              binding:,
              events: [ registration, binding ],
              outcome: "registered"
            )
          )
        end

        def path_conflict(identity, current_binding)
          Failure(
            OutcomeError.new(
              code: :resource_path_conflict,
              message: "Resource path is currently bound to another kind",
              details: {
                repository_id: identity.repository_id,
                normalized_path: identity.normalized_path,
                requested_kind: identity.kind,
                active_resource_id: current_binding.resource_id,
                active_kind: current_binding.kind
              }
            )
          )
        end

        def corrupt(identity, reason)
          Failure(
            OutcomeError.new(
              code: :resource_history_corrupt,
              message: "Resource identity history is inconsistent",
              details: {
                repository_id: identity.repository_id,
                kind: identity.kind,
                normalized_path: identity.normalized_path,
                identity_marker: identity.identity_marker,
                current_path_marker: identity.current_path_marker,
                reason:
              }
            )
          )
        end
      end
    end
  end
end
