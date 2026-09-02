# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshots
    class CommitIdentityV1 < Value
      attribute :document, CommitIdentityDocumentV1
      attribute :registry_id, Types::UuidV7
      attribute :marker, Types::Marker
    end
  end
end
