# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class ObservationState < Value
        Observation = Types.Instance(Events::DevelopmentArtifactObservedV1)
        Correction = Types.Instance(Events::DevelopmentArtifactClassificationCorrectedV1)
        Recorded = Types.Instance(Events::DevelopmentArtifactObservationRecordedV1)
        Link = Types.Instance(Events::DevelopmentArtifactObservationFactLinkedV1)
        CorrectionRecorded = Types.Instance(Events::DevelopmentArtifactClassificationCorrectionRecordedV1)

        attribute :observation, Observation.optional
        attribute :corrections,
                  Types::Array.of(Correction).constrained(
                    max_size: Types::DEVELOPMENT_ARTIFACT_CLASSIFICATION_MAXIMUM_REVISIONS - 1
                  )

        attribute? :recorded, Recorded.optional
        attribute? :link, Link.optional
        attribute? :links, Types::Array.of(Link)
        attribute? :correction_records, Types::Array.of(CorrectionRecorded)

        def self.initial
          new(observation: nil, corrections: [])
        end

        def self.reduce(events)
          observation = nil
          corrections = []
          recorded = link = nil
          links = []
          correction_records = []

          events.each do |event|
            case event
            when Events::DevelopmentArtifactObservationRecordedV1
              raise InvalidDevelopmentArtifactHistory, "Observation was recorded more than once" if recorded

              recorded = event
            when Events::DevelopmentArtifactObservationFactLinkedV1
              raise InvalidDevelopmentArtifactHistory, "Observation link precedes recording" unless recorded
              raise InvalidDevelopmentArtifactHistory, "Observation fact link is duplicated" if links.any? { _1.observed_fact.event_id == event.observed_fact.event_id }

              link = event unless link
              links << event
            when Events::DevelopmentArtifactClassificationCorrectionRecordedV1
              raise InvalidDevelopmentArtifactHistory, "Classification correction precedes observation" unless recorded
              expected_revision = correction_records.length + 2
              unless event.classification_revision == expected_revision &&
                     (event.observation_id.nil? || event.observation_id == recorded.observation_id)
                raise InvalidDevelopmentArtifactHistory, "Artifact classification correction record is not sequential"
              end

              correction_records << event
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

          new(
            observation:,
            corrections:,
            recorded:,
            link:,
            links:,
            correction_records:,
          )
        end

        def self.ensure_recorded!(recorded)
          return if recorded

          raise InvalidDevelopmentArtifactHistory, "Observation property fact precedes recording"
        end

        def classification_revision
          if observation
            corrections.length + 1
          elsif recorded
            correction_records.length + 1
          else
            0
          end
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

        def artifact_id
          links&.first&.artifact_id || observation&.observation&.artifact_id
        end

        def fact_event_ids
          Array(links).map { _1.observed_fact.event_id }
        end
      end
    end
  end
end
