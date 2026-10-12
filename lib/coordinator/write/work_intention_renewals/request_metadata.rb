# frozen_string_literal: true

module Coordinator::Write
  module WorkIntentionRenewals
    class RequestMetadata < EventMetadata
      attribute :task_id, Types::UuidV7.optional
    end
  end
end
