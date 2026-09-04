# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeObservationAuthorizationLinkedV1 < Base
      contract type: "MergeObservationAuthorizationLinked", version: 1

      attribute :merge_snapshot_id, Types::Identifier
      attribute :authorization_id, Types::UuidV7
      attribute :authorization_event, EventReference
    end
  end
end
