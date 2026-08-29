# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class Skills
      def fetch(name:, scope:, revision: nil)
        record = Coordinator::Read::Skill.find_by(name:, scope:)
        return unless record

        snapshot = revision_for(record, revision || record.revision)
        snapshot && build_view(record, snapshot)
      end

      def fetch_asset(name:, scope:, path:, revision: nil)
        record = Coordinator::Read::Skill.find_by(name:, scope:)
        return unless record

        selected_revision = revision || record.revision
        snapshot = revision_for(record, selected_revision)
        return unless snapshot

        asset = Coordinator::Read::SkillAsset.find_by(
          skill_id: record.skill_id,
          revision: selected_revision,
          path:
        )
        asset && build_asset_view(record, snapshot, asset)
      end

      def page(query)
        relation = Coordinator::Read::Skill.all
        relation = relation.where(name: query.name) if query.name
        relation = relation.where(scope: query.scope) if query.scope
        relation = relation.where("skill_id > ?", query.after_skill_id) if query.after_skill_id
        rows = relation.order(:skill_id).page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        selected_rows = rows.first(query.limit)
        snapshots = revisions_for(selected_rows)
        items = selected_rows.filter_map do |record|
          snapshot = snapshots[[ record.skill_id, record.revision ]]
          build_summary(record, snapshot) if snapshot
        end

        SkillPageV1.new(
          items:,
          next_skill_id: has_more ? items.last.skill_id : nil,
          has_more:
        )
      end

      def store_revision(event:, publication:)
        record = Coordinator::Read::Skill.lock.find_by(skill_id: publication.skill_id)
        verify_identity!(record, publication) if record
        verify_tuple_owner!(publication)
        record ||= create_head(publication)
        store_snapshot(event, publication)
        record.update!(revision: publication.revision) if publication.revision > record.revision
        record
      end

      private

      def create_head(publication)
        Coordinator::Read::Skill.create!(
          skill_id: publication.skill_id,
          name: publication.name,
          scope: publication.scope,
          revision: publication.revision
        )
      end

      def store_snapshot(event, publication)
        snapshot = revision_for(publication, publication.revision)
        return snapshot if snapshot

        snapshot = Coordinator::Read::SkillRevision.create!(
          revision_attributes(event, publication)
        )
        store_assets(publication)
        snapshot
      end

      def revision_attributes(event, publication)
        {
          skill_id: publication.skill_id,
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

      def store_assets(publication)
        return if publication.assets.empty?

        Coordinator::Read::SkillAsset.insert_all!(
          publication.assets.map do |asset|
            asset_attributes(asset).merge(
              skill_id: publication.skill_id,
              revision: publication.revision
            )
          end,
          record_timestamps: true
        )
      end

      def asset_attributes(asset)
        if asset.is_a?(Coordinator::Write::Skills::AssetV2)
          content = asset.content
          {
            path: asset.path,
            media_type: content.media_type,
            executable: asset.executable,
            content_encoding: content.encoding,
            content_text: content.respond_to?(:text) ? content.text : nil,
            content_base64: content.respond_to?(:base64) ? content.base64 : nil,
            content_sha256: content.content_sha256,
            byte_size: content.byte_size
          }
        else
          asset.to_h.merge(content_encoding: "binary", content_text: nil)
        end
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

      def revision_for(record, revision)
        Coordinator::Read::SkillRevision.find_by(skill_id: record.skill_id, revision:)
      end

      def revisions_for(records)
        skill_ids = records.map(&:skill_id)
        revisions = records.map(&:revision)
        Coordinator::Read::SkillRevision.where(skill_id: skill_ids, revision: revisions)
          .index_by { [ _1.skill_id, _1.revision ] }
      end

      def build_view(record, snapshot)
        SkillViewV1.new(
          skill_id: record.skill_id,
          name: record.name,
          scope: record.scope,
          revision: snapshot.revision,
          description: snapshot.description,
          instructions: snapshot.instructions,
          assets: Coordinator::Read::SkillAsset.where(
            skill_id: record.skill_id,
            revision: snapshot.revision
          ).order(:path).map do |asset|
            manifest(asset)
          end,
          content_digest: snapshot.content_digest,
          published: source_evidence(snapshot)
        )
      end

      def build_summary(record, snapshot)
        SkillSummaryV1.new(
          skill_id: record.skill_id,
          name: record.name,
          scope: record.scope,
          revision: record.revision,
          description: snapshot.description,
          content_digest: snapshot.content_digest,
          asset_count: snapshot.asset_count,
          published: source_evidence(snapshot)
        )
      end

      def build_asset_view(record, snapshot, asset)
        view = asset.content_encoding == "utf-8" ? SkillTextAssetViewV2 : SkillBinaryAssetViewV2
        content_attribute = asset.content_encoding == "utf-8" ? { text: asset.content_text } : { base64: asset.content_base64 }
        view.new(
          skill_id: record.skill_id,
          name: record.name,
          scope: record.scope,
          revision: snapshot.revision,
          path: asset.path,
          encoding: asset.content_encoding,
          media_type: asset.media_type,
          executable: asset.executable,
          **content_attribute,
          content_sha256: asset.content_sha256,
          byte_size: asset.byte_size,
          published: source_evidence(snapshot)
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
