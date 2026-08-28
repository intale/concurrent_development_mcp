# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class Capture
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, observation_state:, command:, captured_at:)
          capture_result = existing_capture(state, command)
          return capture_result if capture_result.failure?
          capture = capture_result.value!

          observation_result = existing_observation(observation_state, command)
          return observation_result if observation_result.failure?
          observation = observation_result.value!

          capture_event = capture || Events::DevelopmentArtifactCapturedV1.new(
            artifact: command.artifact,
            captured_at:
          )
          observation_event = observation || Events::DevelopmentArtifactObservedV1.new(
            observation: command.observation,
            recorded_at: captured_at
          )
          writes = []
          writes << EventWrite.new(
            stream: @stream_factory.development_artifact(command.artifact.artifact_id),
            event: capture_event
          ) unless capture
          writes << EventWrite.new(
            stream: @stream_factory.development_artifact_observation(command.observation.observation_id),
            event: observation_event
          ) unless observation
          Success(
            CaptureDecisionV1.new(
              capture: capture_event,
              observation: observation_event,
              event_plan: writes.empty? ? nil : EventPlan.new(writes:),
              outcome: capture ? observation ? "existing" : "observed" : "captured"
            )
          )
        end

        private

        def existing_capture(state, command)
          return Success(nil) unless state.capture
          return Success(state.capture) if state.capture.artifact.content == command.artifact.content

          Failure(
            OutcomeError.new(
              code: :development_artifact_identity_conflict,
              message: "Artifact identity is already bound to different immutable content",
              details: { artifact_id: command.artifact.artifact_id }
            )
          )
        end

        def existing_observation(state, command)
          return Success(nil) unless state.observation

          existing = state.observation
          requested = command.observation
          immutable_matches = existing.observation.artifact_id == requested.artifact_id &&
                              existing.observation.scope == requested.scope &&
                              existing.observation.source == requested.source
          unless immutable_matches
            return Failure(
              OutcomeError.new(
                code: :development_artifact_observation_identity_conflict,
                message: "Artifact observation identity is already bound to different immutable provenance",
                details: { observation_id: requested.observation_id }
              )
            )
          end

          classification_matches = state.title == requested.title &&
                                   state.kind == requested.kind &&
                                   state.labels == requested.labels
          return Success(existing) if classification_matches

          Failure(
            OutcomeError.new(
              code: :development_artifact_classification_correction_required,
              message: "Artifact observation classification must be changed through the correction command",
              details: {
                observation_id: requested.observation_id,
                classification_revision: state.classification_revision
              }
            )
          )
        end
      end
    end
  end
end
