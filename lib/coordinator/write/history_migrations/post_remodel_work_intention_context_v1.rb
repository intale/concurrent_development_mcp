# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelWorkIntentionContextV1 < Value
      attribute :target_stream, StreamReference
      attribute :intention_id, Types::UuidV7
      attribute :set, PostRemodelWorkIntentionSetContextV1
      attribute :resource_id, Types::ResourceId
      attribute :resource_kind, Types::ResourceKind
      attribute :resource_path, Types::ResourcePath
    end
  end
end
