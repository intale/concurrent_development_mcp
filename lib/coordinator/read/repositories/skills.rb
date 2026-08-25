# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class Skills
      def fetch(name:, scope:)
        record = Coordinator::Read::Skill.find_by(name:, scope:)
        record && build_view(record)
      end

      def fetch_asset(name:, scope:, path:)
        record = Coordinator::Read::Skill.find_by(name:, scope:)
        return unless record

        asset = Coordinator::Read::SkillAsset.find_by(skill_id: record.skill_id, path:)
        asset && build_asset_view(record, asset)
      end

      def page(query)
        relation = Coordinator::Read::Skill.all
        relation = relation.where(name: query.name) if query.name
        relation = relation.where(scope: query.scope) if query.scope
        relation = relation.where("skill_id > ?", query.after_skill_id) if query.after_skill_id
        rows = relation.order(:skill_id).page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        items = rows.first(query.limit).map { build_summary(_1) }

        SkillPageV1.new(
          items:,
          next_skill_id: has_more ? items.last.skill_id : nil,
          has_more:
        )
      end

      def store_revision(event:, publication:)
        record = Coordinator::Read::Skill.lock.find_by(skill_id: publication.skill_id)
        return record if record && record.revision >= publication.revision

        verify_identity!(record, publication) if record
        verify_tuple_owner!(publication)
        record ||= Coordinator::Read::Skill.new(skill_id: publication.skill_id)
        record.assign_attributes(revision_attributes(event, publication))
        record.save!
        replace_assets(publication)
        record
      end

      private

      def revision_attributes(event, publication)
        {
          name: publication.name,
          scope: publication.scope,
          revision: publication.revision,
          description: publication.description,
          instructions: publication.instructions,
          content_digest: publication.content_digest,
          asset_count: publication.assets.length,
          published_event: event_reference(event).to_h,
          published_actor: actor(event).to_h,
          published_markers: event.markers,
          published_metadata: event.metadata,
          published_causation_id: event.causation_id,
          published_correlation_id: event.correlation_id,
          published_global_position: event.global_position,
          published_at_domain: publication.published_at,
          published_at_store: event.created_at
        }
      end

      def replace_assets(publication)
        Coordinator::Read::SkillAsset.where(skill_id: publication.skill_id).delete_all
        return if publication.assets.empty?

        Coordinator::Read::SkillAsset.insert_all!(
          publication.assets.map do |asset|
            asset.to_h.merge(skill_id: publication.skill_id, revision: publication.revision)
          end,
          record_timestamps: true
        )
      end

      def verify_identity!(record, publication)
        return if record.name == publication.name && record.scope == publication.scope

        raise ProjectionStateError, "Skill identity changed within its source stream"
      end

      def verify_tuple_owner!(publication)
        owner = Coordinator::Read::Skill.find_by(name: publication.name, scope: publication.scope)
        return unless owner && owner.skill_id != publication.skill_id

        raise ProjectionStateError, "Skill name and scope tuple belongs to another source stream"
      end

      def build_view(record)
        SkillViewV1.new(
          skill_id: record.skill_id,
          name: record.name,
          scope: record.scope,
          revision: record.revision,
          description: record.description,
          instructions: record.instructions,
          assets: Coordinator::Read::SkillAsset.where(skill_id: record.skill_id).order(:path).map do |asset|
            manifest(asset)
          end,
          content_digest: record.content_digest,
          published: source_evidence(record)
        )
      end

      def build_summary(record)
        SkillSummaryV1.new(
          skill_id: record.skill_id,
          name: record.name,
          scope: record.scope,
          revision: record.revision,
          description: record.description,
          content_digest: record.content_digest,
          asset_count: record.asset_count,
          published: source_evidence(record)
        )
      end

      def build_asset_view(record, asset)
        SkillAssetViewV1.new(
          skill_id: record.skill_id,
          name: record.name,
          scope: record.scope,
          revision: record.revision,
          path: asset.path,
          media_type: asset.media_type,
          executable: asset.executable,
          content_base64: asset.content_base64,
          content_sha256: asset.content_sha256,
          byte_size: asset.byte_size,
          published: source_evidence(record)
        )
      end

      def manifest(asset)
        SkillAssetManifestV1.new(
          path: asset.path,
          media_type: asset.media_type,
          executable: asset.executable,
          content_sha256: asset.content_sha256,
          byte_size: asset.byte_size
        )
      end

      def source_evidence(record)
        SkillSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.published_event)),
          actor: AttributedActorV1.new(symbolize(record.published_actor)),
          markers: record.published_markers,
          metadata: record.published_metadata,
          global_position: record.published_global_position,
          occurred_at: record.published_at_domain.utc.iso8601(6),
          persisted_at: record.published_at_store.utc.iso8601(6),
          causation_id: record.published_causation_id,
          correlation_id: record.published_correlation_id
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
