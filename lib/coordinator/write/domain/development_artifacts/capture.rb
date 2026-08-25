# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class Capture
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, captured_at:)
          if state.capture
            return existing(state.capture) if state.capture.artifact == command.artifact

            return Failure(
              OutcomeError.new(
                code: :development_artifact_identity_conflict,
                message: "Artifact identity is already bound to different immutable fields",
                details: { artifact_id: command.artifact.artifact_id }
              )
            )
          end

          event = Events::DevelopmentArtifactCapturedV1.new(
            artifact: command.artifact,
            captured_at:
          )
          Success(
            CaptureDecisionV1.new(
              capture: event,
              event_plan: EventPlan.new(
                writes: [
                  EventWrite.new(
                    stream: @stream_factory.development_artifact(command.artifact.artifact_id),
                    event:
                  )
                ]
              ),
              outcome: "captured"
            )
          )
        end

        private

        def existing(capture)
          Success(CaptureDecisionV1.new(capture:, event_plan: nil, outcome: "existing"))
        end
      end
    end
  end
end
