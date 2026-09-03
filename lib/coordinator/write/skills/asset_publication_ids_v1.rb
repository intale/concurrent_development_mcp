# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class AssetPublicationIdsV1 < Value
      attribute :asset_id, Types::UuidV7
      attribute :created_event_id, Types::UuidV7
      attribute :path_event_id, Types::UuidV7
      attribute :content_event_id, Types::UuidV7
      attribute :executability_event_id, Types::UuidV7
      attribute :assignment_event_id, Types::UuidV7
    end
  end
end
