# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class Update
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(artifact_id:, changes:, state:)
          return missing(artifact_id) unless state.created

          writes = []
          changed_properties = []
          if changes.scope && value_of(state.scope, :scope) != changes.scope
            writes << write(artifact_id, Events::DevelopmentArtifactScopeChangedV1.new(artifact_id:, scope: changes.scope))
            changed_properties << "scope"
          end
          if changes.title && value_of(state.title, :title) != changes.title
            writes << write(artifact_id, Events::DevelopmentArtifactTitleChangedV1.new(artifact_id:, title: changes.title))
            changed_properties << "title"
          end
          if changes.kind && value_of(state.kind, :kind) != changes.kind
            writes << write(artifact_id, Events::DevelopmentArtifactKindChangedV1.new(artifact_id:, kind: changes.kind))
            changed_properties << "kind"
          end
          if changes.labels
            existing = Array(state.labels)
            (changes.labels - existing).each do |label|
              writes << write(artifact_id, Events::DevelopmentArtifactLabelAddedV1.new(artifact_id:, label:))
            end
            (existing - changes.labels).each do |label|
              writes << write(artifact_id, Events::DevelopmentArtifactLabelRemovedV1.new(artifact_id:, label:))
            end
            changed_properties << "labels" if changes.labels != existing
          end
          if changes.content && content_changed?(state.content, changes.content, state.content_metadata)
            representation = changes.content.respond_to?(:text) ? changes.content.text : changes.content.base64
            writes << write(artifact_id, Events::DevelopmentArtifactContentChangedV1.new(artifact_id:, content: representation))
            changed_properties << "content"
          end
          if changes.source && source_changed?(state.source, changes.source, state.source_collector)
            source = changes.source
            writes << write(
              artifact_id,
              Events::DevelopmentArtifactSourceChangedV1.new(
                artifact_id:, source_kind: source.kind, locator: source.locator,
                revision: source.revision, observed_at: source.observed_at
              )
            )
            changed_properties << "source"
          end

          Success(
            UpdateDecisionV1.new(
              artifact_id:,
              event_plan: writes.empty? ? nil : EventPlan.new(writes:),
              changed_properties: changed_properties,
              outcome: writes.empty? ? "existing" : "updated"
            )
          )
        end

        private

        def write(artifact_id, event)
          EventWrite.new(stream: @stream_factory.development_artifact(artifact_id), event:)
        end

        def value_of(value, attribute)
          value&.public_send(attribute)
        end

        def content_changed?(current, incoming, current_metadata)
          return true unless current

          incoming_representation = incoming.respond_to?(:text) ? incoming.text : incoming.base64
          current_representation = value_of(current, :content)
          return true unless current_representation == incoming_representation
          # A fact without its server-computed descriptor is
          # not sufficient evidence for a no-op. Re-emit the canonical fact so
          # subsequent decisions can compare the complete representation.
          return true unless current_metadata
          return true if current_metadata[:encoding] && current_metadata[:encoding] != incoming.encoding
          return true if current_metadata[:media_type] && current_metadata[:media_type] != incoming.media_type
          return true if current_metadata[:byte_size] && current_metadata[:byte_size] != incoming.byte_size
          current_metadata[:content_sha256] && current_metadata[:content_sha256] != incoming.content_sha256
        end

        def source_changed?(current, incoming, current_collector)
          return true unless current

          [ value_of(current, :source_kind), value_of(current, :locator), value_of(current, :revision),
            value_of(current, :observed_at), current_collector ] !=
            [ incoming.kind, incoming.locator, incoming.revision, incoming.observed_at, incoming.collector ]
        end

        def missing(artifact_id)
          Failure(
            OutcomeError.new(
              code: :development_artifact_not_found,
              message: "Development Artifact was not found",
              details: { artifact_id: }
            )
          )
        end
      end
    end
  end
end
