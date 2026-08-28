# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class CorrectClassification
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, corrected_at:)
          return observation_missing(command) unless state.observation
          return revision_conflict(state, command) unless state.classification_revision == command.expected_revision

          if state.title == command.title && state.kind == command.kind && state.labels == command.labels
            return Success(existing_decision(state))
          end
          if state.classification_revision >= Types::DEVELOPMENT_ARTIFACT_CLASSIFICATION_MAXIMUM_REVISIONS
            return revision_limit(state, command)
          end

          correction = Events::DevelopmentArtifactClassificationCorrectedV1.new(
            observation_id: command.observation_id,
            artifact_id: state.observation.observation.artifact_id,
            classification_revision: state.classification_revision + 1,
            title: command.title,
            kind: command.kind,
            labels: command.labels.uniq.sort_by(&:b),
            reason: command.reason,
            corrected_at:
          )
          Success(
            ClassificationDecisionV1.new(
              observation: state.observation,
              correction:,
              classification_revision: correction.classification_revision,
              title: correction.title,
              kind: correction.kind,
              labels: correction.labels,
              event_plan: EventPlan.new(
                writes: [
                  EventWrite.new(
                    stream: @stream_factory.development_artifact_observation(command.observation_id),
                    event: correction
                  )
                ]
              ),
              outcome: "corrected"
            )
          )
        end

        private

        def existing_decision(state)
          ClassificationDecisionV1.new(
            observation: state.observation,
            correction: nil,
            classification_revision: state.classification_revision,
            title: state.title,
            kind: state.kind,
            labels: state.labels,
            event_plan: nil,
            outcome: "existing"
          )
        end

        def observation_missing(command)
          Failure(
            OutcomeError.new(
              code: :development_artifact_observation_not_found,
              message: "Development Artifact observation was not found",
              details: { observation_id: command.observation_id }
            )
          )
        end

        def revision_conflict(state, command)
          Failure(
            OutcomeError.new(
              code: :development_artifact_classification_revision_conflict,
              message: "Development Artifact classification revision changed",
              details: {
                observation_id: command.observation_id,
                expected_revision: command.expected_revision,
                current_revision: state.classification_revision
              }
            )
          )
        end

        def revision_limit(state, command)
          Failure(
            OutcomeError.new(
              code: :development_artifact_classification_revision_limit_reached,
              message: "Development Artifact classification revision limit was reached",
              details: {
                observation_id: command.observation_id,
                current_revision: state.classification_revision,
                maximum_revisions: Types::DEVELOPMENT_ARTIFACT_CLASSIFICATION_MAXIMUM_REVISIONS
              }
            )
          )
        end
      end
    end
  end
end
