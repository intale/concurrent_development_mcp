# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class CompleteCompensated
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          denial = denied(state:, command:)
          return denial if denial

          stream = @stream_factory.release_set(command.release_set_id)
          compensation_writes = command.evidence.map do |evidence|
            EventWrite.new(
              stream:,
              event: Events::RepositoryCompensationRecordedV1.new(
                release_set_id: command.release_set_id,
                repository_id: evidence.repository_id,
                integration_event: evidence.integration_event,
                action: evidence.action,
                external_reference: evidence.external_reference
              )
            )
          end
          Success(
            EventPlan.new(
              writes: [
                *compensation_writes,
                EventWrite.new(
                  stream:,
                  event: Events::ReleaseSetOutcomeRecordedV1.new(
                    release_set_id: command.release_set_id,
                    outcome: "compensated"
                  )
                ),
                EventWrite.new(
                  stream:,
                  event: Events::ReleaseSetCompletedV2.new(release_set_id: command.release_set_id)
                )
              ]
            )
          )
        end

        private

        def denied(state:, command:)
          return failure(:release_set_not_found, "ReleaseSet has not been prepared") unless state.preparation
          return failure(:release_set_already_completed, "ReleaseSet is already completed") if state.completed?
          request = state.compensation_request
          return failure(:release_compensation_not_requested, "ReleaseSet compensation has not been requested") unless request
          unless command.compensation_request_event == request.event
            return failure(:release_compensation_request_binding_stale, "Completion does not bind the exact compensation request")
          end
          unless evidence_bindings(command.evidence) == expected_bindings(state, request)
            return failure(:release_compensation_evidence_mismatch, "Compensation evidence must cover each exact integrated member in order")
          end

          nil
        end

        def evidence_bindings(evidence)
          evidence.map { [ _1.repository_id, _1.integration_event ] }
        end

        def expected_bindings(state, request)
          request.successful_integrations.map do |reference|
            integration = state.integrations.find { _1.event == reference }
            [ integration&.payload&.repository_id, reference ]
          end
        end

        def failure(code, message)
          Failure(OutcomeError.new(code:, message:, details: {}))
        end
      end
    end
  end
end
