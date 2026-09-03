# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class CorrectClassificationV2
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, artifact_state: nil, fact_event_references:)
          return missing(command) unless state.recorded || state.observation
          expected = command.expected_revision
          return conflict(state, command) unless state.classification_revision == expected

          artifact_id = state.artifact_id
          return missing(command) unless artifact_id
          current_title = artifact_state ? artifact_property(artifact_state, :title) : state.title
          current_kind = artifact_state ? artifact_property(artifact_state, :kind) : state.kind
          current_labels = artifact_state ? artifact_labels(artifact_state) : Array(state.labels)
          requested_labels = command.labels.uniq.sort_by(&:b)
          title_changed = current_title != command.title
          kind_changed = current_kind != command.kind
          added = requested_labels - current_labels
          removed = current_labels - requested_labels
          return existing(state, command, requested_labels) unless title_changed || kind_changed || added.any? || removed.any?

          revision = expected + 1
          return limit(state, command) if revision > Types::DEVELOPMENT_ARTIFACT_CLASSIFICATION_MAXIMUM_REVISIONS

          return missing(command) unless artifact_state && (artifact_state.created || artifact_state.capture)

          artifact_stream = @stream_factory.development_artifact(artifact_id)
          observation_stream = @stream_factory.development_artifact_observation(command.observation_id)
          artifact_events = []
          artifact_events << Events::DevelopmentArtifactTitleChangedV1.new(
            artifact_id:, title: command.title
          ) if title_changed
          artifact_events << Events::DevelopmentArtifactKindChangedV1.new(
            artifact_id:, kind: command.kind
          ) if kind_changed
          added.each do |label|
            artifact_events << Events::DevelopmentArtifactLabelAddedV1.new(artifact_id:, label:)
          end
          removed.each do |label|
            artifact_events << Events::DevelopmentArtifactLabelRemovedV1.new(artifact_id:, label:)
          end
          fact_event_ids = fact_event_references.map(&:event_id)
          unless fact_event_references.length == artifact_events.length
            raise ArgumentError, "one fact reference is required per classification fact"
          end
          events = artifact_events.map { EventWrite.new(stream: artifact_stream, event: _1) }
          events << EventWrite.new(
            stream: observation_stream,
            event: Events::DevelopmentArtifactClassificationCorrectionRecordedV1.new(
              artifact_id:,
              observation_id: command.observation_id,
              classification_revision: revision,
              reason: command.reason
            )
          )
          events.concat(fact_event_references.each_with_index.map do |fact_reference, index|
            EventWrite.new(
              stream: observation_stream,
              event: Events::DevelopmentArtifactObservationFactLinkedV1.new(
                observation_id: command.observation_id,
                artifact_id:,
                role: fact_role(artifact_events.fetch(index)),
                observed_fact: fact_reference
              )
            )
          end)

          Success(
            ClassificationDecisionV2.new(
              observation_id: command.observation_id,
              artifact_id:,
              classification_revision: revision,
              title: command.title,
              kind: command.kind,
              labels: requested_labels,
              event_plan: EventPlan.new(writes: events),
              fact_event_ids:,
              outcome: "corrected"
            )
          )
        end

        private

        def missing(command)
          Failure(OutcomeError.new(
            code: :development_artifact_observation_not_found,
            message: "Development Artifact observation was not found",
            details: { observation_id: command.observation_id }
          ))
        end

        def conflict(state, command)
          Failure(OutcomeError.new(
            code: :development_artifact_classification_revision_conflict,
            message: "Development Artifact classification revision changed",
            details: {
              observation_id: command.observation_id,
              expected_revision: command.expected_revision,
              current_revision: state.classification_revision
            }
          ))
        end

        def limit(state, command)
          Failure(OutcomeError.new(
            code: :development_artifact_classification_revision_limit_reached,
            message: "Development Artifact classification revision limit was reached",
            details: {
              observation_id: command.observation_id,
              current_revision: state.classification_revision,
              maximum_revisions: Types::DEVELOPMENT_ARTIFACT_CLASSIFICATION_MAXIMUM_REVISIONS
            }
          ))
        end

        def existing(state, command, requested_labels)
          Success(ClassificationDecisionV2.new(
            observation_id: command.observation_id,
            artifact_id: state.artifact_id,
            classification_revision: state.classification_revision,
            title: command.title,
            kind: command.kind,
            labels: requested_labels,
            event_plan: nil,
            fact_event_ids: [],
            outcome: "existing"
          ))
        end

        def artifact_property(state, name)
          event = state.public_send(name)
          event.respond_to?(name) ? event.public_send(name) : event
        end

        def fact_role(event)
          {
            Events::DevelopmentArtifactTitleChangedV1 => "title",
            Events::DevelopmentArtifactKindChangedV1 => "kind",
            Events::DevelopmentArtifactLabelAddedV1 => "label",
            Events::DevelopmentArtifactLabelRemovedV1 => "label"
          }.fetch(event.class)
        end

        def artifact_labels(state)
          Array(state.labels)
        end
      end
    end
  end
end
