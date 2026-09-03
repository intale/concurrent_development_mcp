# frozen_string_literal: true

module Coordinator::Write
  class SkillPublicationPreparationV2 < Value
    AssetIds = Types.Instance(Skills::AssetPublicationIdsV1)

    attribute :recorded_at, Types::Timestamp
    attribute :input_digest, Types::Sha256Digest
    attribute :skill_revision_id, Types::UuidV7
    attribute :registration_event_id, Types::UuidV7
    attribute :revision_created_event_id, Types::UuidV7
    attribute :description_event_id, Types::UuidV7
    attribute :instructions_event_id, Types::UuidV7
    attribute :asset_ids, Types::Array.of(AssetIds).constrained(max_size: Types::SKILL_ASSET_MAXIMUM_COUNT)
    attribute :publication_event_id, Types::UuidV7
  end
end
