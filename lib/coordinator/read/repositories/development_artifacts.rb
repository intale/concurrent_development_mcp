# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class DevelopmentArtifacts
      RELATION_OBSERVED_SEQUENCE_SQL = "development_artifact_relations.observed_sequence"
      INITIAL_OBSERVATION_FACT_ROLES = %w[created scope title kind source content].freeze
      SUPERSESSION_OBSERVED_SEQUENCE_SQL =
        "development_artifact_relation_supersessions.observed_sequence"
      CURRENT_OBSERVED_SEQUENCE_SQL =
        "GREATEST(#{RELATION_OBSERVED_SEQUENCE_SQL}, " \
        "COALESCE(#{SUPERSESSION_OBSERVED_SEQUENCE_SQL}, 0))"
      OBSERVATION_TABLE_SQL = "development_artifact_observations"

      def initialize(
        relation_registry: Coordinator::Shared::DevelopmentArtifactRelationRegistry.new,
        follow_action: DevelopmentArtifactRelationFollowAction.new,
        projection_timestamp: ProjectionTimestamp.new
      )
        @relation_registry = relation_registry
        @follow_action = follow_action
        @projection_timestamp = projection_timestamp
      end

      def fetch(artifact_id, observation_id: nil)
        artifact = Coordinator::Read::DevelopmentArtifact.find_by(artifact_id:)
        return unless artifact

        observations = complete_observations.where(artifact_id:)
        observations = observations.where(observation_id:) if observation_id
        observation = observations.order(observed_global_position: :desc, observation_id: :desc).first
        observation && build_view(artifact, observation)
      end

      # Granular artifact facts intentionally project one property at a time.
      # The write-side event data remains cohesive; this repository is the
      # read-side adapter that folds those facts into the current view.
      def store_created(event:, created:)
        record = Coordinator::Read::DevelopmentArtifact.find_or_initialize_by(
          artifact_id: created.artifact_id
        )
        return record if record.persisted? && record.captured_event.present?

        record.assign_attributes(
          captured_event: event_reference(event).to_h,
          captured_actor: actor(event).to_h,
          captured_markers: event.markers,
          captured_metadata: event.metadata,
          captured_causation_id: event.causation_id,
          captured_correlation_id: event.correlation_id,
          captured_global_position: event.global_position,
          captured_at_domain: event.created_at,
          captured_at_store: event.created_at,
          stream_revision: [ record.stream_revision.to_i, event.stream_revision ].max
        )
        save_projection!(record, event)
        record
      end

      def store_property(event:, fact:)
        record = Coordinator::Read::DevelopmentArtifact.find_or_initialize_by(artifact_id: fact.artifact_id)
        attributes = case fact
        when Coordinator::Write::Events::DevelopmentArtifactScopeChangedV1
          { scope: fact.scope }
        when Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1
          { title: fact.title }
        when Coordinator::Write::Events::DevelopmentArtifactKindChangedV1
          { kind: fact.kind }
        when Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1
          { labels: (Array(record.labels) | [ fact.label ]).sort }
        when Coordinator::Write::Events::DevelopmentArtifactLabelRemovedV1
          { labels: Array(record.labels) - [ fact.label ] }
        when Coordinator::Write::Events::DevelopmentArtifactSourceChangedV1
          {
            source_kind: fact.source_kind,
            source_locator: fact.locator,
            source_revision: fact.revision,
            source_observed_at: fact.observed_at,
            source_collector: event.metadata["collector"]
          }
        when Coordinator::Write::Events::DevelopmentArtifactContentChangedV1
          {
            content_encoding: event.metadata.fetch("encoding"),
            content_media_type: event.metadata.fetch("media_type"),
            content_text: event.metadata.fetch("encoding") == "utf-8" ? fact.content : nil,
            content_base64: event.metadata.fetch("encoding") == "binary" ? fact.content : nil,
            content_sha256: event.metadata.fetch("content_sha256"),
            content_byte_size: event.metadata.fetch("byte_size")
          }
        else
          raise InvalidProjectionSource, "Unsupported granular Artifact fact #{fact.class.name}"
        end
        record.artifact_id = fact.artifact_id
        record.stream_revision = [ record.stream_revision.to_i, event.stream_revision ].max
        record.assign_attributes(attributes)
        save_projection!(record, event)
        record
      end

      def store_observation_recorded(event:, recorded:)
        record = Coordinator::Read::DevelopmentArtifactObservation.find_or_initialize_by(
          observation_id: recorded.observation_id
        )
        return record if record.observed_event&.fetch("event_id", nil) == event.id

        attributes = {
          **observed_evidence_attributes(event, occurred_at: event.created_at),
          current_global_position: [ record.current_global_position.to_i, event.global_position ].max
        }
        if record.classified_event.blank?
          attributes.merge!(
            classification_revision: [ record.classification_revision.to_i, 1 ].max,
            classification_reason: nil,
            **classified_evidence_attributes(event, occurred_at: event.created_at)
          )
        end
        record.assign_attributes(attributes)
        save_projection!(record, event)
        record
      end

      def store_classification_recorded(event:, correction:)
        observation_id = correction.observation_id
        return unless observation_id

        record = Coordinator::Read::DevelopmentArtifactObservation.find_or_initialize_by(
          observation_id:
        )
        if record.artifact_id && record.artifact_id != correction.artifact_id
          raise ProjectionStateError, "Artifact classification changed observation identity"
        end
        if record.classification_revision > correction.classification_revision
          return record
        end
        if record.classification_revision == correction.classification_revision && record.classified_event
          return record if record.classification_reason == correction.reason

          raise ProjectionStateError, "Artifact classification revision changed across events"
        end

        assign_observation_change(
          record,
          {
            artifact_id: correction.artifact_id,
            classification_revision: correction.classification_revision,
            classification_reason: correction.reason,
            **classified_evidence_attributes(event, occurred_at: event.created_at)
          },
          global_position: event.global_position,
          event:
        )
      end

      def store_observation_fact_link(event:, link:, observed_fact_event:, observed_fact:)
        record = Coordinator::Read::DevelopmentArtifactObservation.find_or_initialize_by(
          observation_id: link.observation_id
        )
        if record.artifact_id && record.artifact_id != link.artifact_id
          raise ProjectionStateError, "Artifact observation changed identity"
        end

        link_record = Coordinator::Read::DevelopmentArtifactObservationFactLink.find_or_initialize_by(
          link_event_id: event.id
        )
        return record if link_record.persisted?

        link_record.assign_attributes(
          observation_id: link.observation_id,
          artifact_id: link.artifact_id,
          role: link.role,
          link_event: event_reference(event).to_h,
          link_actor: actor(event).to_h,
          link_markers: event.markers,
          link_metadata: event.metadata,
          link_causation_id: event.causation_id,
          link_correlation_id: event.correlation_id,
          link_global_position: event.global_position,
          link_at_domain: event.created_at,
          link_at_store: event.created_at,
          observed_fact_event: event_reference(observed_fact_event).to_h,
          observed_fact_event_id: observed_fact_event.id,
          observed_fact_data: observed_fact.to_h,
          observed_fact_metadata: observed_fact_event.metadata,
          observed_fact_created_at: observed_fact_event.created_at
        )
        link_record.updated_at = event.created_at
        link_record.save!(touch: false)

        record.assign_attributes(artifact_id: link.artifact_id)
        apply_observed_fact!(record, observed_fact, fact_event: observed_fact_event)
        record.current_global_position = [ record.current_global_position.to_i, event.global_position ].max
        save_projection!(record, event)
        record
      end

      def store_relation_v2(event:, declaration:)
        relation = Coordinator::Read::DevelopmentArtifactRelation.find_or_initialize_by(
          relation_id: declaration.relation_id
        )
        relation.assign_attributes(
          source_artifact_id: declaration.source_artifact_id,
          relation: declaration.relation,
          target_kind: declaration.target_kind,
          target_id: declaration.target_id,
          target_status: target_status_for(declaration.target_kind),
          path: declaration.path,
          fragment: declaration.fragment,
          normalized_locator: declaration.normalized_locator,
          declared_event: event_reference(event).to_h,
          declared_actor: actor(event).to_h,
          declared_markers: event.markers,
          declared_metadata: event.metadata,
          declared_causation_id: event.causation_id,
          declared_correlation_id: event.correlation_id,
          declared_global_position: event.global_position,
          declared_at_domain: event.created_at,
          declared_at_store: event.created_at
        )
        save_projection!(relation, event)
        relation
      end

      def store_supersession_v2(event:, supersession:)
        relation = Coordinator::Read::DevelopmentArtifactRelation.find_by(
          relation_id: supersession.relation_id
        )
        return unless relation

        record = Coordinator::Read::DevelopmentArtifactRelationSupersession.find_or_initialize_by(
          superseded_relation_id: supersession.relation_id
        )
        return record if record.persisted?

        attributes = {
          source_artifact_id: supersession.source_artifact_id,
          replacement_relation_id: supersession.replacement_relation_id,
          reason: supersession.reason,
          superseded_event: event_reference(event).to_h,
          superseded_actor: actor(event).to_h,
          superseded_markers: event.markers,
          superseded_metadata: event.metadata,
          superseded_causation_id: event.causation_id,
          superseded_correlation_id: event.correlation_id,
          superseded_global_position: event.global_position,
          superseded_at_domain: event.created_at,
          superseded_at_store: event.created_at,
          observed_sequence: next_relation_observed_sequence
        }
        record.assign_attributes(attributes)
        save_projection!(record, event)
        record
      end

      def fetch_content(artifact_id, observation_id: nil)
        if observation_id
          observation = Coordinator::Read::DevelopmentArtifactObservation.find_by(
            observation_id:, artifact_id:
          )
          return unless observation&.content_encoding

          return build_content(observation)
        end

        record = Coordinator::Read::DevelopmentArtifact.find_by(artifact_id:)
        return unless record&.content_encoding

        build_content(record)
      end

      def page(query)
        relation = complete_observations.includes(:artifact)
        relation = relation.where(scope: query.scope) if query.scope
        relation = relation.where(kind: query.kind) if query.kind
        relation = relation.where(source_kind: query.source_kind) if query.source_kind
        if query.labels.any?
          relation = relation.where(
            "#{OBSERVATION_TABLE_SQL}.labels @> ?::jsonb",
            JSON.generate(query.labels)
          )
        end
        relation = relation.where(
          artifact_id: relation_target_source_ids(query)
        ) if query.relation_target_kind
        if query.after_global_position
          relation = relation.where(
            "#{OBSERVATION_TABLE_SQL}.current_global_position > ?",
            query.after_global_position
          )
        end

        rows = relation
          .order("#{OBSERVATION_TABLE_SQL}.current_global_position", "#{OBSERVATION_TABLE_SQL}.observation_id")
          .page(1)
          .per(query.limit + 1)
          .to_a
        has_more = rows.length > query.limit
        visible_rows = rows.first(query.limit)
        counts = relationship_capacity_counts(visible_rows.map(&:artifact_id))
        items = visible_rows.map do |record|
          build_summary(record, record.artifact, relationship_counts: counts.fetch(record.artifact_id))
        end
        DevelopmentArtifactPageV1.new(
          items:,
          next_global_position: has_more ? rows.fetch(query.limit - 1).current_global_position : nil,
          has_more:
        )
      end

      def event_time_page(query)
        relation = complete_observations.includes(:artifact)
        relation = relation.where(scope: query.scope) if query.scope
        relation = relation.where(kind: query.kind) if query.kind
        relation = relation.where(source_kind: query.source_kind) if query.source_kind
        if query.labels.any?
          relation = relation.where(
            "#{OBSERVATION_TABLE_SQL}.labels @> ?::jsonb",
            JSON.generate(query.labels)
          )
        end
        if query.after_updated_at
          relation = relation.where(
            "#{OBSERVATION_TABLE_SQL}.updated_at < :updated_at OR " \
            "(#{OBSERVATION_TABLE_SQL}.updated_at = :updated_at AND " \
            "#{OBSERVATION_TABLE_SQL}.observation_id < :observation_id)",
            updated_at: query.after_updated_at,
            observation_id: query.after_observation_id
          )
        end
        rows = relation
          .order("#{OBSERVATION_TABLE_SQL}.updated_at DESC", "#{OBSERVATION_TABLE_SQL}.observation_id DESC")
          .limit(query.first + 1)
          .to_a
        has_more = rows.length > query.first
        visible_rows = rows.first(query.first)
        counts = relationship_capacity_counts(visible_rows.map(&:artifact_id))
        items = visible_rows.map do |record|
          build_summary(record, record.artifact, relationship_counts: counts.fetch(record.artifact_id))
        end
        last = visible_rows.last

        Coordinator::Read::Web::KnowledgeBrowserV1::ArtifactPage.new(
          items:,
          next_cursor: has_more ? Coordinator::Read::Web::KnowledgeBrowserV1::ArtifactCursor.new(
            updated_at: last.updated_at.utc.iso8601(6),
            observation_id: last.observation_id
          ) : nil,
          has_more:
        )
      end

      def relation_page(query)
        cursor = query.cursor
        base = navigation_scope(query)
        upper = cursor.through_observed_sequence || maximum_observed_sequence(
          base,
          include_superseded: query.include_superseded
        )
        observed_sequence_sql = observed_sequence_at(upper)
        window = base.where(
          "#{observed_sequence_sql} > ? AND #{observed_sequence_sql} <= ?",
          cursor.after_observed_sequence,
          upper
        )
        window = active_at(window, upper) unless query.include_superseded
        window = after_declaration(window, cursor)
        rows = window
          .select(
            "development_artifact_relations.*",
            "#{observed_sequence_sql} AS navigation_sequence",
            "#{superseded_at(upper)} AS navigation_superseded"
          )
          .includes(:supersession)
          .order(:declared_global_position, :relation_id)
          .limit(query.limit + 1)
          .to_a
        window_has_more = rows.length > query.limit
        visible_rows = rows.first(query.limit)
        summaries = summaries_for(query.artifact_id, visible_rows)
        items = visible_rows.map { build_navigation_relation(_1, query.artifact_id, summaries) }
        continuation = continuation_cursor(
          cursor:,
          upper:,
          items: visible_rows,
          window_has_more:
        )
        has_more = window_has_more || maximum_observed_sequence(
          base,
          include_superseded: query.include_superseded
        ) > upper

        DevelopmentArtifactRelationPageV1.new(
          artifact: summaries[query.artifact_id],
          items:,
          continuation_cursor: continuation,
          has_more:
        )
      end

      def locator_page(query)
        cursor = query.cursor
        base = exact_locator_scope(query)
        resolution = locator_resolution(base)
        upper = cursor.through_observed_sequence || maximum_artifact_observed_sequence(base)
        window = base.where(
          "#{OBSERVATION_TABLE_SQL}.observed_sequence > ? AND " \
            "#{OBSERVATION_TABLE_SQL}.observed_sequence <= ?",
          cursor.after_observed_sequence,
          upper
        )
        window = after_observation_change(window, cursor)
        rows = window
          .includes(:artifact)
          .order("#{OBSERVATION_TABLE_SQL}.current_global_position", "#{OBSERVATION_TABLE_SQL}.observation_id")
          .limit(query.limit + 1)
          .to_a
        window_has_more = rows.length > query.limit
        visible_rows = rows.first(query.limit)
        counts = relationship_capacity_counts(visible_rows.map(&:artifact_id))
        items = visible_rows.map do |record|
          build_summary(record, record.artifact, relationship_counts: counts.fetch(record.artifact_id))
        end
        continuation = locator_continuation_cursor(
          cursor:,
          upper:,
          items: visible_rows,
          window_has_more:
        )
        has_more = window_has_more || maximum_artifact_observed_sequence(base) > upper

        DevelopmentArtifactLocatorPageV1.new(
          resolution:,
          items:,
          continuation_cursor: continuation,
          has_more:
        )
      end

      def store_capture(event:, capture:)
        artifact = capture.artifact
        record = Coordinator::Read::DevelopmentArtifact.find_by(artifact_id: artifact.artifact_id)
        verify_artifact!(record, artifact) if record
        record ||= Coordinator::Read::DevelopmentArtifact.new(artifact_id: artifact.artifact_id)
        record.assign_attributes(capture_attributes(event, capture))
        record.stream_revision = [ record.stream_revision.to_i, event.stream_revision ].max
        save_projection!(record, event)
        record
      end

      def store_observation(event:, observed:)
        observation = observed.observation
        record = Coordinator::Read::DevelopmentArtifactObservation.find_or_initialize_by(
          observation_id: observation.observation_id
        )
        verify_observation_identity!(record, observation) if record.artifact_id
        return record if record.observed_event&.fetch("event_id") == event.id

        attributes = observation_attributes(event, observed)
        if record.classification_revision <= 1
          attributes.merge!(
            classification_attributes(
              event,
              title: observation.title,
              kind: observation.kind,
              labels: observation.labels,
              revision: 1,
              reason: nil,
              occurred_at: observed.recorded_at
            )
          )
        end
        assign_observation_change(record, attributes, global_position: event.global_position, event:)
      end

      def store_classification(event:, correction:)
        record = Coordinator::Read::DevelopmentArtifactObservation.find_or_initialize_by(
          observation_id: correction.observation_id
        )
        if record.artifact_id && record.artifact_id != correction.artifact_id
          raise ProjectionStateError, "Artifact classification changed observation identity"
        end
        if record.classification_revision > correction.classification_revision
          return record
        end
        if record.classification_revision == correction.classification_revision && record.classified_event
          verify_classification!(record, correction)
          return record
        end

        attributes = {
          artifact_id: correction.artifact_id,
          classification_revision: correction.classification_revision,
          title: correction.title,
          kind: correction.kind,
          labels: correction.labels
        }.merge(
          classification_attributes(
            event,
            title: correction.title,
            kind: correction.kind,
            labels: correction.labels,
            revision: correction.classification_revision,
            reason: correction.reason,
            occurred_at: correction.corrected_at
          )
        )
        assign_observation_change(record, attributes, global_position: event.global_position, event:)
      end

      def store_relation(event:, declaration:)
        relation = declaration.artifact_relation
        record = Coordinator::Read::DevelopmentArtifactRelation.find_by(
          relation_id: relation.relation_id
        )
        verify_relation!(record, relation) if record
        record ||= Coordinator::Read::DevelopmentArtifactRelation.new(
          relation_id: relation.relation_id
        )
        record.assign_attributes(relation_attributes(event, declaration))
        save_projection!(record, event)
        record
      end

      def store_supersession(event:, supersession:)
        record = Coordinator::Read::DevelopmentArtifactRelationSupersession.find_by(
          superseded_relation_id: supersession.superseded_relation_id
        )
        if record
          verify_supersession!(record, supersession)
          return record
        end

        record = Coordinator::Read::DevelopmentArtifactRelationSupersession.new(
          superseded_relation_id: supersession.superseded_relation_id
        )
        record.assign_attributes(
          supersession_attributes(event, supersession).merge(
            observed_sequence: next_relation_observed_sequence
          )
        )
        save_projection!(record, event)
        record
      end

      private

      def exact_locator_scope(query)
        relation = complete_observations.where(
          scope: query.scope,
          source_kind: query.source_kind,
          source_locator: query.locator
        )
        return relation unless query.revision_specified

        relation.where(source_revision: query.source_revision)
      end

      def locator_resolution(relation)
        case relation.limit(2).pluck(:observation_id).length
        when 0 then "absent"
        when 1 then "unique"
        else "ambiguous"
        end
      end

      def maximum_artifact_observed_sequence(relation)
        relation.maximum(Arel.sql("#{OBSERVATION_TABLE_SQL}.observed_sequence")) || 0
      end

      def after_observation_change(relation, cursor)
        return relation unless cursor.after_current_global_position

        relation.where(
          "(#{OBSERVATION_TABLE_SQL}.current_global_position, " \
            "#{OBSERVATION_TABLE_SQL}.observation_id) > (?, ?)",
          cursor.after_current_global_position,
          cursor.after_observation_id
        )
      end

      def locator_continuation_cursor(cursor:, upper:, items:, window_has_more:)
        if window_has_more
          last = items.last
          return DevelopmentArtifactLocatorPageV1::Cursor.new(
            after_observed_sequence: cursor.after_observed_sequence,
            through_observed_sequence: upper,
            after_current_global_position: last.current_global_position,
            after_observation_id: last.observation_id
          )
        end

        DevelopmentArtifactLocatorPageV1::Cursor.new(
          after_observed_sequence: upper,
          through_observed_sequence: nil,
          after_current_global_position: nil,
          after_observation_id: nil
        )
      end

      def navigation_scope(query)
        relation = Coordinator::Read::DevelopmentArtifactRelation.left_outer_joins(:supersession)
        relation = direction_scope(relation, query)
        relation = relation.where(relation: query.relation) if query.relation
        relation
      end

      def direction_scope(relation, query)
        table = Coordinator::Read::DevelopmentArtifactRelation.table_name
        outgoing = "#{table}.source_artifact_id = :artifact_id"
        incoming = "#{table}.target_kind = 'artifact' AND #{table}.target_id = :artifact_id"
        predicate =
          case query.direction
          when "outgoing" then outgoing
          when "incoming" then incoming
          else "(#{outgoing}) OR (#{incoming})"
          end
        relation.where(predicate, artifact_id: query.artifact_id)
      end

      def maximum_observed_sequence(relation, include_superseded:)
        relation = active_at(relation, nil) unless include_superseded
        relation.maximum(Arel.sql(CURRENT_OBSERVED_SEQUENCE_SQL)) || 0
      end

      def observed_sequence_at(upper)
        "CASE WHEN #{superseded_at(upper)} " \
          "THEN #{SUPERSESSION_OBSERVED_SEQUENCE_SQL} " \
          "ELSE #{RELATION_OBSERVED_SEQUENCE_SQL} END"
      end

      def superseded_at(upper)
        return "#{SUPERSESSION_OBSERVED_SEQUENCE_SQL} IS NOT NULL" unless upper

        "#{SUPERSESSION_OBSERVED_SEQUENCE_SQL} IS NOT NULL AND " \
          "#{SUPERSESSION_OBSERVED_SEQUENCE_SQL} <= #{Integer(upper)}"
      end

      def active_at(relation, upper)
        relation.where("NOT (#{superseded_at(upper)})")
      end

      def after_declaration(relation, cursor)
        return relation unless cursor.after_declared_global_position

        relation.where(
          "(development_artifact_relations.declared_global_position, " \
          "development_artifact_relations.relation_id) > (?, ?)",
          cursor.after_declared_global_position,
          cursor.after_relation_id
        )
      end

      def continuation_cursor(cursor:, upper:, items:, window_has_more:)
        if window_has_more
          last = items.last
          return DevelopmentArtifactRelationPageV1::Cursor.new(
            after_observed_sequence: cursor.after_observed_sequence,
            through_observed_sequence: upper,
            after_declared_global_position: last.declared_global_position,
            after_relation_id: last.relation_id
          )
        end

        DevelopmentArtifactRelationPageV1::Cursor.new(
          after_observed_sequence: upper,
          through_observed_sequence: nil,
          after_declared_global_position: nil,
          after_relation_id: nil
        )
      end

      def relation_target_source_ids(query)
        active_relations.where(
          target_kind: query.relation_target_kind,
          target_id: query.relation_target_id
        ).select(:source_artifact_id)
      end

      def capture_attributes(event, capture)
        artifact = capture.artifact
        {
          scope: artifact.scope,
          title: artifact.title,
          kind: artifact.kind,
          labels: artifact.labels,
          **content_attributes(artifact.content),
          source_kind: artifact.source.kind,
          source_locator: artifact.source.locator,
          source_revision: artifact.source.revision,
          source_observed_at: artifact.source.observed_at,
          source_collector: artifact.source.collector,
          captured_event: event_reference(event).to_h,
          captured_actor: actor(event).to_h,
          captured_markers: event.markers,
          captured_metadata: event.metadata,
          captured_causation_id: event.causation_id,
          captured_correlation_id: event.correlation_id,
          captured_global_position: event.global_position,
          captured_at_domain: capture.captured_at,
          captured_at_store: event.created_at
        }
      end

      def content_attributes(content)
        {
          content_encoding: content.encoding,
          content_media_type: content.media_type,
          content_text: content.respond_to?(:text) ? content.text : nil,
          content_base64: content.respond_to?(:base64) ? content.base64 : nil,
          content_sha256: content.content_sha256,
          content_byte_size: content.byte_size
        }
      end

      def observation_attributes(event, observed)
        observation_value_attributes(observed.observation).merge(
          observed_evidence_attributes(event, occurred_at: observed.recorded_at)
        )
      end

      def observation_value_attributes(observation)
        {
          artifact_id: observation.artifact_id,
          scope: observation.scope,
          source_kind: observation.source.kind,
          source_locator: observation.source.locator,
          source_revision: observation.source.revision,
          source_observed_at: observation.source.observed_at,
          source_collector: observation.source.collector
        }
      end

      def classification_attributes(event, title:, kind:, labels:, revision:, reason:, occurred_at:)
        {
          title:,
          kind:,
          labels:,
          classification_revision: revision,
          classification_reason: reason
        }.merge(classified_evidence_attributes(event, occurred_at:))
      end

      def observed_evidence_attributes(event, occurred_at:)
        evidence_attributes(event, prefix: "observed", occurred_at:)
      end

      def classified_evidence_attributes(event, occurred_at:)
        evidence_attributes(event, prefix: "classified", occurred_at:)
      end

      def evidence_attributes(event, prefix:, occurred_at:)
        {
          "#{prefix}_event": event_reference(event).to_h,
          "#{prefix}_actor": actor(event).to_h,
          "#{prefix}_markers": event.markers,
          "#{prefix}_metadata": event.metadata,
          "#{prefix}_causation_id": event.causation_id,
          "#{prefix}_correlation_id": event.correlation_id,
          "#{prefix}_global_position": event.global_position,
          "#{prefix}_at_domain": occurred_at,
          "#{prefix}_at_store": event.created_at
        }
      end

      def assign_observation_change(record, attributes, global_position:, event:)
        attributes[:current_global_position] = [ record.current_global_position.to_i, global_position ].max
        attributes[:observed_sequence] = next_artifact_observed_sequence if record.persisted?
        record.assign_attributes(attributes)
        save_projection!(record, event)
        record
      end

      def apply_observed_fact!(record, fact, fact_event:)
        attributes = case fact
        when Coordinator::Write::Events::DevelopmentArtifactScopeChangedV1
          { scope: fact.scope }
        when Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1
          { title: fact.title }
        when Coordinator::Write::Events::DevelopmentArtifactKindChangedV1
          { kind: fact.kind }
        when Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1
          { labels: (Array(record.labels) | [ fact.label ]).sort }
        when Coordinator::Write::Events::DevelopmentArtifactLabelRemovedV1
          { labels: Array(record.labels) - [ fact.label ] }
        when Coordinator::Write::Events::DevelopmentArtifactSourceChangedV1
          {
            source_kind: fact.source_kind,
            source_locator: fact.locator,
            source_revision: fact.revision,
            source_observed_at: fact.observed_at,
            source_collector: fact_event.metadata.fetch("collector")
          }
        when Coordinator::Write::Events::DevelopmentArtifactContentChangedV1
          {
            content_encoding: fact_event.metadata.fetch("encoding"),
            content_media_type: fact_event.metadata.fetch("media_type"),
            content_text: fact_event.metadata.fetch("encoding") == "utf-8" ? fact.content : nil,
            content_base64: fact_event.metadata.fetch("encoding") == "binary" ? fact.content : nil,
            content_sha256: fact_event.metadata.fetch("content_sha256"),
            content_byte_size: fact_event.metadata.fetch("byte_size")
          }
        else
          {}
        end
        record.assign_attributes(attributes)
      end

      def save_projection!(record, event)
        record.updated_at = @projection_timestamp.call(current: record.updated_at, event:)
        record.save!(touch: false)
      end

      def relation_attributes(event, declaration)
        relation = declaration.artifact_relation
        {
          source_artifact_id: relation.source_artifact_id,
          relation: relation.relation,
          target_kind: relation.target.kind,
          target_id: relation.target.id,
          target_status: relation.target.status,
          target_name: relation.target.name,
          target_scope: relation.target.scope,
          path: relation.relation_attributes.path,
          fragment: relation.relation_attributes.fragment,
          normalized_locator: relation.relation_attributes.normalized_locator,
          declared_event: event_reference(event).to_h,
          declared_actor: actor(event).to_h,
          declared_markers: event.markers,
          declared_metadata: event.metadata,
          declared_causation_id: event.causation_id,
          declared_correlation_id: event.correlation_id,
          declared_global_position: event.global_position,
          declared_at_domain: declaration.declared_at,
          declared_at_store: event.created_at
        }
      end

      def target_status_for(target_kind)
        target_kind == "external" ? "unverified" : "verified"
      end

      def supersession_attributes(event, supersession)
        {
          source_artifact_id: supersession.source_artifact_id,
          replacement_relation_id: supersession.replacement_relation_id,
          reason: supersession.reason,
          superseded_event: event_reference(event).to_h,
          superseded_actor: actor(event).to_h,
          superseded_markers: event.markers,
          superseded_metadata: event.metadata,
          superseded_causation_id: event.causation_id,
          superseded_correlation_id: event.correlation_id,
          superseded_global_position: event.global_position,
          superseded_at_domain: supersession.superseded_at,
          superseded_at_store: event.created_at
        }
      end

      def verify_artifact!(record, artifact)
        expected = content_attributes(artifact.content)
        matches = expected.all? { |attribute, value| record.public_send(attribute) == value }
        return if matches

        raise ProjectionStateError, "Artifact identity changed across capture events"
      end

      def verify_observation_identity!(record, observation)
        matches = record.artifact_id == observation.artifact_id
        if matches && record.observed_event
          matches = record.scope == observation.scope &&
                    record.source_kind == observation.source.kind &&
                    record.source_locator == observation.source.locator &&
                    record.source_revision == observation.source.revision &&
                    record.source_observed_at.utc.iso8601(6) == observation.source.observed_at &&
                    record.source_collector == observation.source.collector
        end
        return if matches

        raise ProjectionStateError, "Artifact observation identity changed across events"
      end

      def verify_classification!(record, correction)
        matches = record.artifact_id == correction.artifact_id &&
                  record.title == correction.title &&
                  record.kind == correction.kind &&
                  record.labels == correction.labels &&
                  record.classification_reason == correction.reason
        return if matches

        raise ProjectionStateError, "Artifact classification revision changed across events"
      end

      def verify_relation!(record, relation)
        attributes = relation.relation_attributes
        matches = record.source_artifact_id == relation.source_artifact_id &&
                  record.relation == relation.relation &&
                  record.target_kind == relation.target.kind &&
                  record.target_id == relation.target.id &&
                  record.target_status == relation.target.status &&
                  record.target_name == relation.target.name &&
                  record.target_scope == relation.target.scope &&
                  record.path == attributes.path &&
                  record.fragment == attributes.fragment &&
                  record.normalized_locator == attributes.normalized_locator
        return if matches

        raise ProjectionStateError, "Artifact relation identity changed across declaration events"
      end

      def verify_supersession!(record, supersession)
        matches = record.source_artifact_id == supersession.source_artifact_id &&
                  record.replacement_relation_id == supersession.replacement_relation_id &&
                  record.reason == supersession.reason
        return if matches

        raise ProjectionStateError, "Artifact relation supersession changed across events"
      end

      def build_view(record, observation)
        relations = Coordinator::Read::DevelopmentArtifactRelation
          .where(source_artifact_id: record.artifact_id)
          .includes(:supersession)
          .order(:declared_global_position, :relation_id)
          .to_a
        summaries = summaries_for(record.artifact_id, relations)
        summaries[record.artifact_id] = build_summary(observation, record)
        DevelopmentArtifactViewV1.new(
          artifact: summaries.fetch(record.artifact_id),
          relationships: relations.map do |relation|
            build_navigation_relation(relation, record.artifact_id, summaries)
          end
        )
      end

      def build_summary(observation, artifact, relationship_counts: nil)
        counts = relationship_counts || relationship_capacity_counts([ artifact.artifact_id ])
          .fetch(artifact.artifact_id)
        content = observation.content_encoding ? observation : artifact
        DevelopmentArtifactSummaryV1.new(
          artifact_id: artifact.artifact_id,
          stream_revision: artifact.stream_revision,
          observation_id: observation.observation_id,
          scope: observation.scope,
          title: observation.title,
          kind: observation.kind,
          labels: observation.labels,
          media_type: content.content_media_type,
          encoding: content.content_encoding,
          content_sha256: content.content_sha256,
          byte_size: content.content_byte_size,
          source: provenance(observation),
          classification_revision: observation.classification_revision,
          classification_reason: observation.classification_reason,
          relationship_count: counts.fetch(:active),
          relationship_capacity: relationship_capacity(counts),
          captured: evidence(artifact, "captured"),
          observed: evidence(observation, "observed"),
          classified: evidence(observation, "classified")
        )
      end

      def build_content(record)
        view = record.content_encoding == "utf-8" ?
          DevelopmentArtifactTextContentViewV2 : DevelopmentArtifactBinaryContentViewV2
        content_attribute = record.content_encoding == "utf-8" ?
          { text: record.content_text } : { base64: record.content_base64 }
        view.new(
          artifact_id: record.artifact_id,
          encoding: record.content_encoding,
          media_type: record.content_media_type,
          **content_attribute,
          content_sha256: record.content_sha256,
          byte_size: record.content_byte_size
        )
      end

      def build_navigation_relation(record, artifact_id, summaries)
        direction = record.source_artifact_id == artifact_id ? "outgoing" : "incoming"
        peer_kind = direction == "outgoing" ? record.target_kind : "artifact"
        peer_id = direction == "outgoing" ? record.target_id : record.source_artifact_id
        supersession = visible_supersession(record)
        definition = @relation_registry.fetch(record.relation)
        target = relation_target(record)
        DevelopmentArtifactRelationViewV1.new(
          relation_id: record.relation_id,
          source_artifact_id: record.source_artifact_id,
          relation: record.relation,
          display_relation: direction == "outgoing" ? definition.relation : definition.inverse,
          inverse_relation: definition.inverse,
          transitive: definition.transitive,
          supersedable: definition.supersedable,
          target:,
          attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(
            path: record.path,
            fragment: record.fragment,
            normalized_locator: record.normalized_locator
          ),
          direction:,
          peer_kind:,
          peer_id:,
          peer_artifact: peer_kind == "artifact" ? summaries[peer_id] : nil,
          status: supersession ? "superseded" : "active",
          observed_sequence: record[:navigation_sequence] || effective_sequence(record),
          declared: evidence(record, "declared"),
          replacement_relation_id: supersession&.replacement_relation_id,
          supersession_reason: supersession&.reason,
          superseded: supersession && evidence(supersession, "superseded"),
          follow_action: @follow_action.call(
            direction:,
            source_artifact_id: record.source_artifact_id,
            target:
          )
        )
      end

      def effective_sequence(record)
        record.supersession&.observed_sequence || record.observed_sequence
      end

      def relation_target(record)
        attributes = {
          kind: record.target_kind,
          id: record.target_id,
          status: record.target_status,
          name: record.target_name,
          scope: record.target_scope
        }
        case record.target_kind
        when "skill"
          skill = Coordinator::Read::Skill.find_by(skill_id: record.target_id)
          attributes[:name] ||= skill&.name
          attributes[:scope] ||= skill&.scope
        when "repository"
          repository = Coordinator::Read::Repository.find_by(repository_id: record.target_id)
          attributes[:name] ||= repository_key(repository)
          attributes[:scope] ||= repository&.scope
        end
        Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(**attributes)
      end

      def repository_key(repository)
        repository&.registered_markers&.find { _1.start_with?("repository-key:") }
          &.delete_prefix("repository-key:")
      end

      def visible_supersession(record)
        return record.supersession unless record.has_attribute?("navigation_superseded")

        record[:navigation_superseded] ? record.supersession : nil
      end

      def next_relation_observed_sequence
        connection = Coordinator::Read::DevelopmentArtifactRelation.connection
        table = connection.quote(Coordinator::Read::DevelopmentArtifactRelation.table_name)
        column = connection.quote("observed_sequence")
        connection.select_value(
          "SELECT nextval(pg_get_serial_sequence(#{table}, #{column}))"
        ).to_i
      end

      def next_artifact_observed_sequence
        connection = Coordinator::Read::DevelopmentArtifactObservation.connection
        table = connection.quote(Coordinator::Read::DevelopmentArtifactObservation.table_name)
        column = connection.quote("observed_sequence")
        connection.select_value(
          "SELECT nextval(pg_get_serial_sequence(#{table}, #{column}))"
        ).to_i
      end

      def summaries_for(artifact_id, relations)
        peer_ids = relations.filter_map do |relation|
          if relation.source_artifact_id == artifact_id
            relation.target_id if relation.target_kind == "artifact"
          else
            relation.source_artifact_id
          end
        end
        ids = ([ artifact_id ] + peer_ids).uniq
        observations = complete_observations
          .where(artifact_id: ids)
          .includes(:artifact)
          .order("#{OBSERVATION_TABLE_SQL}.observed_global_position", "#{OBSERVATION_TABLE_SQL}.observation_id")
          .to_a
          .index_by(&:artifact_id)
        counts = relationship_capacity_counts(ids)
        observations.transform_values do |observation|
          build_summary(
            observation,
            observation.artifact,
            relationship_counts: counts.fetch(observation.artifact_id)
          )
        end
      end

      def relationship_capacity_counts(artifact_ids)
        ids = artifact_ids.uniq
        active = active_relations.where(source_artifact_id: ids).group(:source_artifact_id).count
        lifetime = Coordinator::Read::DevelopmentArtifactRelation
          .where(source_artifact_id: ids)
          .group(:source_artifact_id)
          .count
        ids.to_h do |artifact_id|
          [ artifact_id, { active: active.fetch(artifact_id, 0), lifetime: lifetime.fetch(artifact_id, 0) } ]
        end
      end

      def relationship_capacity(counts)
        active = counts.fetch(:active)
        lifetime = counts.fetch(:lifetime)
        DevelopmentArtifactRelationshipCapacityV1.new(
          active_count: active,
          active_limit: Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT,
          active_remaining: [
            Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT - active,
            0
          ].max,
          lifetime_count: lifetime,
          lifetime_limit: Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT,
          lifetime_remaining: [
            Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT - lifetime,
            0
          ].max
        )
      end

      def complete_observations
        relation = Coordinator::Read::DevelopmentArtifactObservation.joins(:artifact)
        %i[
          observed_event artifact_id scope title kind source_kind source_locator
          source_observed_at source_collector classified_event classified_actor
          classified_global_position classified_at_domain classified_at_store
        ].each { |column| relation = relation.where.not(column => nil) }
        %i[content_encoding content_media_type content_sha256 content_byte_size].each do |column|
          relation = relation.where.not(development_artifacts: { column => nil })
        end
        granular_requirements = INITIAL_OBSERVATION_FACT_ROLES.map do |role|
          escaped_role = role.gsub("'", "''")
          "EXISTS (SELECT 1 FROM development_artifact_observation_fact_links " \
            "WHERE development_artifact_observation_fact_links.observation_id = " \
            "development_artifact_observations.observation_id AND " \
            "development_artifact_observation_fact_links.role = '#{escaped_role}')"
        end.join(" AND ")
        completeness_sql = [
          "development_artifact_observations.observed_event ->> 'type' = :legacy_type OR (",
          "development_artifact_observations.content_encoding IS NOT NULL AND ",
          "development_artifact_observations.content_media_type IS NOT NULL AND ",
          "development_artifact_observations.content_sha256 IS NOT NULL AND ",
          "development_artifact_observations.content_byte_size IS NOT NULL AND ",
          granular_requirements,
          ")"
        ].join
        relation.where(
          completeness_sql,
          legacy_type: "DevelopmentArtifactObserved"
        )
      end

      def active_relations
        Coordinator::Read::DevelopmentArtifactRelation.where.not(
          relation_id: Coordinator::Read::DevelopmentArtifactRelationSupersession
            .select(:superseded_relation_id)
        )
      end

      def provenance(record)
        DevelopmentArtifactProvenanceV1.new(
          kind: record.source_kind,
          locator: record.source_locator,
          revision: record.source_revision,
          observed_at: record.source_observed_at.utc.iso8601(6),
          collector: record.source_collector
        )
      end

      def evidence(record, prefix)
        DevelopmentArtifactEventEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.public_send("#{prefix}_event"))),
          actor: AttributedActorV1.new(symbolize(record.public_send("#{prefix}_actor"))),
          markers: record.public_send("#{prefix}_markers"),
          metadata: record.public_send("#{prefix}_metadata"),
          global_position: record.public_send("#{prefix}_global_position"),
          occurred_at: record.public_send("#{prefix}_at_domain").utc.iso8601(6),
          persisted_at: record.public_send("#{prefix}_at_store").utc.iso8601(6),
          causation_id: record.public_send("#{prefix}_causation_id"),
          correlation_id: record.public_send("#{prefix}_correlation_id")
        )
      end

      def actor(event)
        AttributedActorV1.new(
          kind: event.metadata.fetch("actor_kind"),
          id: event.metadata.fetch("actor_id"),
          authenticated: false
        )
      end

      def event_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array then value.map { symbolize(_1) }
        else value
        end
      end
    end
  end
end
