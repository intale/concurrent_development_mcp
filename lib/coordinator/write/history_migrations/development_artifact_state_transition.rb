# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DevelopmentArtifactStateTransition
      def call(state:, source:, source_event:)
        values = values_from(state, source)
        added = (values.fetch(:labels) - state.labels.map(&:label)).sort_by(&:b)
        removed = (state.labels.map(&:label) - values.fetch(:labels)).sort_by(&:b)
        source_kind = source_kind(source)
        reference = event_reference(source_event)

        next_labels = state.labels.reject { removed.include?(_1.label) }
        next_labels.concat(
          added.each_with_index.map do |label, index|
            DevelopmentArtifactLabelStateV1.new(
              label:,
              origin: origin(
                role: "label",
                event_type: "DevelopmentArtifactLabelAdded",
                step_name: DevelopmentArtifactPropertySteps.label_added(source_kind, index),
                source_event: reference
              )
            )
          end
        )

        scope_changed = state.scope != values.fetch(:scope)
        title_changed = state.title != values.fetch(:title)
        kind_changed = state.kind != values.fetch(:kind)
        source_changed = state.source != values.fetch(:source)
        next_state = DevelopmentArtifactSourceStateV1.new(
          legacy_artifact_id: state.legacy_artifact_id,
          scope: values.fetch(:scope),
          title: values.fetch(:title),
          kind: values.fetch(:kind),
          source: values.fetch(:source),
          content: state.content,
          created_origin: state.created_origin,
          scope_origin: changed_origin(
            state.scope_origin,
            changed: scope_changed,
            role: "scope",
            event_type: "DevelopmentArtifactScopeChanged",
            source_kind:,
            source_event: reference
          ),
          title_origin: changed_origin(
            state.title_origin,
            changed: title_changed,
            role: "title",
            event_type: "DevelopmentArtifactTitleChanged",
            source_kind:,
            source_event: reference
          ),
          kind_origin: changed_origin(
            state.kind_origin,
            changed: kind_changed,
            role: "kind",
            event_type: "DevelopmentArtifactKindChanged",
            source_kind:,
            source_event: reference
          ),
          source_origin: changed_origin(
            state.source_origin,
            changed: source_changed,
            role: "source",
            event_type: "DevelopmentArtifactSourceChanged",
            source_kind:,
            source_event: reference
          ),
          content_origin: state.content_origin,
          labels: next_labels.sort_by { _1.label.b }.freeze
        )

        DevelopmentArtifactTransitionV1.new(
          state: next_state,
          scope_changed:,
          title_changed:,
          kind_changed:,
          source_changed:,
          added_labels: added.freeze,
          removed_labels: removed.freeze
        )
      end

      private

      def values_from(state, source)
        case source
        when LegacyEvents::DevelopmentArtifactObservedV1
          observation = source.observation
          {
            scope: observation.scope,
            title: observation.title,
            kind: observation.kind,
            source: observation.source,
            labels: observation.labels
          }
        when LegacyEvents::DevelopmentArtifactClassificationCorrectedV1
          {
            scope: state.scope,
            title: source.title,
            kind: source.kind,
            source: state.source,
            labels: source.labels
          }
        else
          raise ArgumentError, "unsupported Development Artifact transition #{source.class.name}"
        end
      end

      def source_kind(source)
        case source
        when LegacyEvents::DevelopmentArtifactObservedV1 then "observation"
        when LegacyEvents::DevelopmentArtifactClassificationCorrectedV1 then "classification"
        else raise ArgumentError, "unsupported Development Artifact transition #{source.class.name}"
        end
      end

      def changed_origin(existing, changed:, role:, event_type:, source_kind:, source_event:)
        return existing unless changed

        origin(
          role:,
          event_type:,
          step_name: DevelopmentArtifactPropertySteps.property(role, source_kind),
          source_event:
        )
      end

      def origin(role:, event_type:, step_name:, source_event:)
        DevelopmentArtifactPropertyOriginV1.new(role:, event_type:, step_name:, source_event:)
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end
    end
  end
end
