# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Repositories
      class Register
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(registration:, command:, registered_at:)
          return conflict(registration, command) if registration

          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.repository(command.repository_id),
                  event: Events::RepositoryRegisteredV1.new(
                    repository_id: command.repository_id,
                    scope: command.scope,
                    display_name: command.display_name,
                    paths: command.paths,
                    remotes: command.remotes,
                    registered_at:
                  )
                )
              ]
            )
          )
        end

        private

        def conflict(registration, command)
          same_identity = registration.repository_id == command.repository_id &&
                          registration.scope == command.scope &&
                          registration.display_name == command.display_name &&
                          registration.paths == command.paths &&
                          registration.remotes == command.remotes
          code = same_identity ? :repository_already_registered : :repository_identity_conflict
          message =
            if same_identity
              "Repository is already registered; reuse the original command only after an unknown outcome"
            else
              "Repository ID is already bound to another exact registration"
            end

          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: {
                repository_id: command.repository_id,
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
