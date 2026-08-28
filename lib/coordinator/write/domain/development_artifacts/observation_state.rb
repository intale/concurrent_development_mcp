# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class ObservationState < Value
        Observation = Types.Instance(Events::DevelopmentArtifactObservedV1)
        Correction = Types.Instance(Events::DevelopmentArtifactClassificationCorrectedV1)

        attribute :observation, Observation.optional
        attribute :corrections,
                  Types::Array.of(Correction).constrained(
                    max_size: Types::DEVELOPMENT_ARTIFACT_CLASSIFICATION_MAXIMUM_REVISIONS - 1
                  )

        def self.initial
          new(observation: nil, corrections: [])
        end

        def self.reduce(events)
          observation = nil
          corrections = []

          events.each do |event|
            case event
            when Events::DevelopmentArtifactObservedV1
              raise InvalidDevelopmentArtifactHistory, "Artifact observation was recorded more than once" if observation

              observation = event
            when Events::DevelopmentArtifactClassificationCorrectedV1
              raise InvalidDevelopmentArtifactHistory, "Classification correction precedes observation" unless observation

              expected_revision = corrections.length + 2
              unless event.observation_id == observation.observation.observation_id &&
                     event.artifact_id == observation.observation.artifact_id &&
                     event.classification_revision == expected_revision
                raise InvalidDevelopmentArtifactHistory, "Artifact classification correction is not sequential"
              end

              corrections << event
            else
              raise InvalidDevelopmentArtifactHistory, "Unexpected Artifact observation event #{event.class.name}"
            end
          end

          new(observation:, corrections:)
        end

        def classification_revision
          observation ? corrections.length + 1 : 0
        end

        def title
          corrections.last&.title || observation&.observation&.title
        end

        def kind
          corrections.last&.kind || observation&.observation&.kind
        end

        def labels
          corrections.last&.labels || observation&.observation&.labels
        end
      end
    end
  end
end
