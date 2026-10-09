# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class ObservationState < Value
        Recorded = Types.Instance(Events::DevelopmentArtifactObservationRecordedV1)
        Link = Types.Instance(Events::DevelopmentArtifactObservationFactLinkedV1)
        CorrectionRecorded = Types.Instance(Events::DevelopmentArtifactClassificationCorrectionRecordedV1)

        attribute? :recorded, Recorded.optional
        attribute? :link, Link.optional
        attribute? :links, Types::Array.of(Link)
        attribute? :correction_records, Types::Array.of(CorrectionRecorded)

        def self.initial
          new(links: [], correction_records: [])
        end

        def self.reduce(events)
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
            else
              raise InvalidDevelopmentArtifactHistory, "Unexpected Artifact observation event #{event.class.name}"
            end
          end

          new(
            recorded:,
            link:,
            links:,
            correction_records:,
          )
        end

        def classification_revision
          recorded ? correction_records.length + 1 : 0
        end

        def artifact_id
          links.first&.artifact_id
        end

        def fact_event_ids
          links.map { _1.observed_fact.event_id }
        end
      end
    end
  end
end
