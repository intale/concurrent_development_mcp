# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class DevelopmentArtifacts
      OBSERVED_SEQUENCE_SQL = "development_artifact_relations.observed_sequence"

      def fetch(artifact_id)
        record = Coordinator::Read::DevelopmentArtifact.find_by(artifact_id:)
        record && build_view(record)
      end

      def fetch_content(artifact_id)
        record = Coordinator::Read::DevelopmentArtifact.find_by(artifact_id:)
        record && build_content(record)
      end

      def page(query)
        relation = Coordinator::Read::DevelopmentArtifact.all
        relation = relation.where(scope: query.scope) if query.scope
        relation = relation.where(kind: query.kind) if query.kind
        relation = relation.where(source_kind: query.source_kind) if query.source_kind
        relation = relation.where("labels @> ?::jsonb", JSON.generate(query.labels)) if query.labels.any?
        relation = relation.where(
          artifact_id: relation_target_source_ids(query)
        ) if query.relation_target_kind
        if query.after_global_position
          relation = relation.where("captured_global_position > ?", query.after_global_position)
        end

        rows = relation.order(:captured_global_position).page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        items = rows.first(query.limit).map { build_summary(_1) }
        DevelopmentArtifactPageV1.new(
          items:,
          next_global_position: has_more ? items.last.captured.global_position : nil,
          has_more:
        )
      end

      def relation_page(query)
        cursor = query.cursor
        base = navigation_scope(query)
        upper = cursor.through_observed_sequence || maximum_observed_sequence(base)
        window = base.where(
          "#{OBSERVED_SEQUENCE_SQL} > ? AND #{OBSERVED_SEQUENCE_SQL} <= ?",
          cursor.after_observed_sequence,
          upper
        )
        window = after_declaration(window, cursor)
        rows = window
          .select(
            "development_artifact_relations.*",
            "#{OBSERVED_SEQUENCE_SQL} AS navigation_sequence"
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
        has_more = window_has_more || maximum_observed_sequence(base) > upper

        DevelopmentArtifactRelationPageV1.new(
          artifact: summaries[query.artifact_id],
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
        record.save!
        record
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
        record.save!
        record
      end

      def store_supersession(event:, supersession:)
        record = Coordinator::Read::DevelopmentArtifactRelationSupersession.find_by(
          superseded_relation_id: supersession.superseded_relation_id
        )
        verify_supersession!(record, supersession) if record
        record ||= Coordinator::Read::DevelopmentArtifactRelationSupersession.new(
          superseded_relation_id: supersession.superseded_relation_id
        )
        record.assign_attributes(supersession_attributes(event, supersession))
        record.save!
        record
      end

      private

      def navigation_scope(query)
        relation = Coordinator::Read::DevelopmentArtifactRelation.left_outer_joins(:supersession)
        relation = direction_scope(relation, query)
        relation = relation.where(relation: query.relation) if query.relation
        unless query.include_superseded
          relation = relation.where(
            development_artifact_relation_supersessions: { superseded_relation_id: nil }
          )
        end
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

      def maximum_observed_sequence(relation)
        relation.maximum(Arel.sql(OBSERVED_SEQUENCE_SQL)) || 0
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
          content_encoding: artifact.content.encoding,
          content_media_type: artifact.content.media_type,
          content_base64: artifact.content.content_base64,
          content_sha256: artifact.content.content_sha256,
          content_byte_size: artifact.content.byte_size,
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

      def relation_attributes(event, declaration)
        relation = declaration.artifact_relation
        {
          source_artifact_id: relation.source_artifact_id,
          relation: relation.relation,
          target_kind: relation.target.kind,
          target_id: relation.target.id,
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
        matches = record.scope == artifact.scope &&
                  record.source_kind == artifact.source.kind &&
                  record.source_locator == artifact.source.locator &&
                  record.content_sha256 == artifact.content.content_sha256
        return if matches

        raise ProjectionStateError, "Artifact identity changed across capture events"
      end

      def verify_relation!(record, relation)
        attributes = relation.relation_attributes
        matches = record.source_artifact_id == relation.source_artifact_id &&
                  record.relation == relation.relation &&
                  record.target_kind == relation.target.kind &&
                  record.target_id == relation.target.id &&
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

      def build_view(record)
        relations = Coordinator::Read::DevelopmentArtifactRelation
          .where(source_artifact_id: record.artifact_id)
          .includes(:supersession)
          .order(:declared_global_position, :relation_id)
          .to_a
        summaries = summaries_for(record.artifact_id, relations)
        DevelopmentArtifactViewV1.new(
          artifact: summaries.fetch(record.artifact_id),
          relationships: relations.map do |relation|
            build_navigation_relation(relation, record.artifact_id, summaries)
          end
        )
      end

      def build_summary(record, relationship_count: nil)
        DevelopmentArtifactSummaryV1.new(
          artifact_id: record.artifact_id,
          scope: record.scope,
          title: record.title,
          kind: record.kind,
          labels: record.labels,
          media_type: record.content_media_type,
          encoding: record.content_encoding,
          content_sha256: record.content_sha256,
          byte_size: record.content_byte_size,
          source: provenance(record),
          relationship_count: relationship_count || active_relations.where(
            source_artifact_id: record.artifact_id
          ).count,
          captured: evidence(record, "captured")
        )
      end

      def build_content(record)
        text =
          if record.content_encoding == "utf-8"
            record.content_base64.unpack1("m0").force_encoding(Encoding::UTF_8)
          end
        DevelopmentArtifactContentViewV1.new(
          artifact_id: record.artifact_id,
          encoding: record.content_encoding,
          media_type: record.content_media_type,
          text:,
          base64: record.content_encoding == "binary" ? record.content_base64 : nil,
          content_sha256: record.content_sha256,
          byte_size: record.content_byte_size
        )
      end

      def build_navigation_relation(record, artifact_id, summaries)
        direction = record.source_artifact_id == artifact_id ? "outgoing" : "incoming"
        peer_kind = direction == "outgoing" ? record.target_kind : "artifact"
        peer_id = direction == "outgoing" ? record.target_id : record.source_artifact_id
        supersession = record.supersession
        DevelopmentArtifactRelationViewV1.new(
          relation_id: record.relation_id,
          source_artifact_id: record.source_artifact_id,
          relation: record.relation,
          target: Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
            kind: record.target_kind,
            id: record.target_id
          ),
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
          superseded: supersession && evidence(supersession, "superseded")
        )
      end

      def effective_sequence(record)
        record.observed_sequence
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
        records = Coordinator::Read::DevelopmentArtifact.where(artifact_id: ids).index_by(&:artifact_id)
        counts = active_relations.where(source_artifact_id: ids).group(:source_artifact_id).count
        records.transform_values do |record|
          build_summary(record, relationship_count: counts.fetch(record.artifact_id, 0))
        end
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
