# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      # Builds the initial Artifact and Observation facts. It deliberately does not
      # add timestamps or derived content descriptors to event data.
      class GranularCapture
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(artifact:, observation:, fact_event_references:)
          artifact_stream = @stream_factory.development_artifact(artifact.artifact_id)
          artifact_writes = [
            EventWrite.new(
              stream: artifact_stream,
              event: Events::DevelopmentArtifactCreatedV1.new(
                artifact_id: artifact.artifact_id
              )
            ),
            EventWrite.new(
              stream: artifact_stream,
              event: Events::DevelopmentArtifactScopeChangedV1.new(
                artifact_id: artifact.artifact_id,
                scope: artifact.scope
              )
            ),
            EventWrite.new(
              stream: artifact_stream,
              event: Events::DevelopmentArtifactTitleChangedV1.new(
                artifact_id: artifact.artifact_id,
                title: artifact.title
              )
            ),
            EventWrite.new(
              stream: artifact_stream,
              event: Events::DevelopmentArtifactKindChangedV1.new(
                artifact_id: artifact.artifact_id,
                kind: artifact.kind
              )
            ),
            source_write(artifact),
            content_write(artifact)
          ]
          artifact_writes.concat(
            artifact.labels.map do |label|
              EventWrite.new(
                stream: artifact_stream,
                event: Events::DevelopmentArtifactLabelAddedV1.new(
                  artifact_id: artifact.artifact_id,
                  label:
                )
              )
            end
          )
          fact_event_ids = fact_event_references.map(&:event_id)
          raise ArgumentError, "one fact reference is required per artifact fact" unless
            fact_event_references.length == artifact_writes.length
          observation_stream = @stream_factory.development_artifact_observation(observation.observation_id)
          writes = artifact_writes + [
            EventWrite.new(
              stream: observation_stream,
              event: Events::DevelopmentArtifactObservationRecordedV1.new(
                observation_id: observation.observation_id
              )
            )
          ]
          writes.concat(fact_event_references.each_with_index.map do |fact_reference, index|
            EventWrite.new(
              stream: observation_stream,
              event: Events::DevelopmentArtifactObservationFactLinkedV1.new(
                observation_id: observation.observation_id,
                artifact_id: artifact.artifact_id,
                role: fact_role(artifact_writes.fetch(index).event),
                observed_fact: fact_reference
              )
            )
          end)

          Success(
            GranularCaptureDecisionV1.new(
              artifact:,
              observation:,
              artifact_id: artifact.artifact_id,
              observation_id: observation.observation_id,
              event_plan: EventPlan.new(writes:),
              fact_event_ids:,
              outcome: "created"
            )
          )
        end

        private

        def fact_role(event)
          {
            Events::DevelopmentArtifactCreatedV1 => "created",
            Events::DevelopmentArtifactScopeChangedV1 => "scope",
            Events::DevelopmentArtifactTitleChangedV1 => "title",
            Events::DevelopmentArtifactKindChangedV1 => "kind",
            Events::DevelopmentArtifactSourceChangedV1 => "source",
            Events::DevelopmentArtifactContentChangedV1 => "content",
            Events::DevelopmentArtifactLabelAddedV1 => "label"
          }.fetch(event.class)
        end

        def source_write(artifact)
          EventWrite.new(
            stream: @stream_factory.development_artifact(artifact.artifact_id),
            event: Events::DevelopmentArtifactSourceChangedV1.new(
              artifact_id: artifact.artifact_id,
              source_kind: artifact.source.kind,
              locator: artifact.source.locator,
              revision: artifact.source.revision,
              observed_at: artifact.source.observed_at
            )
          )
        end

        def content_write(artifact)
          content = artifact.content
          # The representation is deliberately a single event fact.  ContentV1
          # metadata describes whether it is text or binary; no second event
          # type is needed for the representation.
          representation = content.respond_to?(:text) ? content.text : content.base64
          event = Events::DevelopmentArtifactContentChangedV1.new(
                artifact_id: artifact.artifact_id,
                content: representation
          )
          EventWrite.new(
            stream: @stream_factory.development_artifact(artifact.artifact_id),
            event:
          )
        end
      end
    end
  end
end
