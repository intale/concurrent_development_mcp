# frozen_string_literal: true

module Coordinator::Write
  module WorkIntentionRenewals
    class ChildMetadata < EventMetadata
      attribute :renewal_id, Types::UuidV7
    end
  end
end
