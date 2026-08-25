# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class DevelopmentArtifacts
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

      private

      def relation_target_source_ids(query)
        Coordinator::Read::DevelopmentArtifactRelation
          .where(target_kind: query.relation_target_kind, target_id: query.relation_target_id)
          .select(:source_artifact_id)
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

      def verify_artifact!(record, artifact)
        matches = record.scope == artifact.scope &&
                  record.source_kind == artifact.source.kind &&
                  record.source_locator == artifact.source.locator &&
                  record.content_sha256 == artifact.content.content_sha256
        return if matches

        raise ProjectionStateError, "Artifact identity changed across capture events"
      end

      def verify_relation!(record, relation)
        matches = record.source_artifact_id == relation.source_artifact_id &&
                  record.relation == relation.relation &&
                  record.target_kind == relation.target.kind &&
                  record.target_id == relation.target.id &&
                  record.path == relation.relation_attributes.path
        return if matches

        raise ProjectionStateError, "Artifact relation identity changed across declaration events"
      end

      def build_view(record)
        DevelopmentArtifactViewV1.new(
          artifact: build_summary(record),
          relationships: Coordinator::Read::DevelopmentArtifactRelation
            .where(source_artifact_id: record.artifact_id)
            .order(:declared_global_position)
            .map { build_relation(_1) }
        )
      end

      def build_summary(record)
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
          relationship_count: Coordinator::Read::DevelopmentArtifactRelation.where(
            source_artifact_id: record.artifact_id
          ).count,
          captured: evidence(record, "captured")
        )
      end

      def build_content(record)
        text = if record.content_encoding == "utf-8"
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

      def build_relation(record)
        DevelopmentArtifactRelationViewV1.new(
          relation_id: record.relation_id,
          source_artifact_id: record.source_artifact_id,
          relation: record.relation,
          target: Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
            kind: record.target_kind,
            id: record.target_id
          ),
          attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(
            path: record.path
          ),
          declared: evidence(record, "declared")
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
