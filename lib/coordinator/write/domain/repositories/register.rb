# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Repositories
      class Register
        include Dry::Monads[:result]

        class DecisionV1 < Value
          Registration = Types.Instance(RepositoryRegistrationV2)
          Plan = Types.Instance(EventPlan)

          attribute :registration, Registration
          attribute :event_plan, Plan.optional
          attribute :outcome, Types::String.enum("registered", "existing")
        end

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(registration_by_key:, registration_by_id:, command:)
          if registration_by_key
            return conflict(registration_by_key, command) unless
              compatible?(registration_by_key, registration_by_id, command)

            return Success(
              DecisionV1.new(
                registration: registration_by_key,
                event_plan: nil,
                outcome: "existing"
              )
            )
          end

          return conflict(registration_by_id, command) if registration_by_id

          registration = RepositoryRegistrationV2.new(
            repository_id: command.repository_id,
            scope: command.scope,
            repository_key: command.repository_key,
            display_name: command.display_name,
            paths: command.paths,
            remotes: command.remotes
          )

          events = [
            Events::RepositoryRegisteredV2.new(
              repository_id: command.repository_id,
              scope: command.scope,
              repository_key: command.repository_key
            )
          ]
          events << Events::RepositoryDisplayNameChangedV1.new(
            repository_id: command.repository_id,
            display_name: command.display_name
          ) if command.display_name
          command.paths.each do |path|
            events << Events::RepositoryPathAddedV1.new(repository_id: command.repository_id, path:)
          end
          command.remotes.each do |remote|
            events << Events::RepositoryRemoteAddedV1.new(repository_id: command.repository_id, remote:)
          end

          Success(
            DecisionV1.new(
              registration:,
              event_plan: EventPlan.new(
                writes: events.map do |event|
                  EventWrite.new(stream: @stream_factory.repository(command.repository_id), event:)
                end
              ),
              outcome: "registered"
            )
          )
        end

        private

        def compatible?(registration_by_key, registration_by_id, command)
          same_proposed_identity = registration_by_id.nil? ||
                                   registration_by_id.repository_id == registration_by_key.repository_id

          same_proposed_identity &&
            registration_by_key.scope == command.scope &&
            registration_by_key.repository_key == command.repository_key &&
            registration_by_key.display_name == command.display_name &&
            registration_by_key.paths == command.paths &&
            registration_by_key.remotes == command.remotes
        end

        def conflict(registration, command)
          Failure(
            OutcomeError.new(
              code: :repository_identity_conflict,
              message: "Repository key or proposed UUID is already bound to another exact registration",
              details: {
                repository_id: registration.repository_id,
                requested_scope: command.scope,
                registered_scope: registration.scope
              }
            )
          )
        end
      end
    end
  end
end
