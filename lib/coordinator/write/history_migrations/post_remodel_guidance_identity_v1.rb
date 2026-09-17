# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelGuidanceIdentityV1 < Value
      attribute :target_stream, StreamReference
      attribute :message_id, Types::UuidV7
    end
  end
end
