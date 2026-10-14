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

      def fetch_by_id(skill_id, revision: nil)
        record = Coordinator::Read::Skill.find_by(skill_id:)
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

      def fetch_asset_by_id(skill_id:, path:, revision: nil)
        record = Coordinator::Read::Skill.find_by(skill_id:)
        return unless record

        selected_revision = revision || record.revision
        snapshot = revision_for(record, selected_revision)
        return unless snapshot

        asset = Coordinator::Read::SkillAsset.find_by(skill_id:, revision: selected_revision, path:)
        asset && build_asset_view(record, snapshot, asset)
      end

      def page(query)
        relation = Coordinator::Read::Skill.all
        relation = relation.where(name: query.name) if query.name
        relation = relation.where(scope: query.scope) if query.scope
        if query.order == "updated_at" && query.after_skill_id
          comparator = query.sort == "oldest_first" ? ">" : "<"
          relation = relation.where(
            "updated_at #{comparator} :updated_at OR (updated_at = :updated_at AND skill_id #{comparator} :id)",
            updated_at: query.after_updated_at,
            id: query.after_skill_id
          )
        end
        direction = query.sort == "oldest_first" ? :asc : :desc
        relation = query.order == "updated_at" ? relation.order(updated_at: direction, skill_id: direction) : relation.order(:skill_id)
        if query.order == "skill_id" && query.after_skill_id
          relation = relation.where("skill_id > ?", query.after_skill_id)
        end
        rows = relation.page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        selected_rows = rows.first(query.limit)
        snapshots = revisions_for(selected_rows)
        items = selected_rows.filter_map do |record|
          snapshot = snapshots[[ record.skill_id, record.revision ]]
          build_summary(record, snapshot) if snapshot
        end

        SkillPageV1.new(
          items:,
          next_updated_at: has_more && query.order == "updated_at" ? selected_rows.last.updated_at.utc.iso8601(6) : nil,
          next_skill_id: has_more ? items.last.skill_id : nil,
          has_more:
        )
      end

      private

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
