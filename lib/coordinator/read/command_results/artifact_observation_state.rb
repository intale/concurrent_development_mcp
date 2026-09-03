# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class ArtifactObservationState < Value
      Observation = Types.Instance(Coordinator::Write::Events::DevelopmentArtifactObservedV1)
      Correction = Types.Instance(
        Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectedV1
      )

      attribute :observation, Observation
      attribute :corrections, Types::Array.of(Correction)

      def self.reduce(events)
        observation = events.find do |event|
          event.is_a?(Coordinator::Write::Events::DevelopmentArtifactObservedV1)
        end
        raise InvalidProjectionSource, "Artifact observation source is missing" unless observation

        corrections = events.filter_map do |event|
          event if event.is_a?(
            Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectedV1
          )
        end
        new(observation:, corrections:)
      end

      def classification_revision
        corrections.length + 1
      end

      def title
        corrections.last&.title || observation.observation.title
      end

      def kind
        corrections.last&.kind || observation.observation.kind
      end

      def labels
        corrections.last&.labels || observation.observation.labels
      end
    end
  end
end
