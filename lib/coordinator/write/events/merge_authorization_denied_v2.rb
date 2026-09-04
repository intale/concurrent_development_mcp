# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeAuthorizationDeniedV2 < Base
      contract type: "MergeAuthorizationDenied", version: 2

      attribute :authorization_id, Types::UuidV7
      attribute :merge_snapshot_id, Types::Identifier
      attribute :evaluation, MergeAuthorizations::EvaluationV1
      attribute :snapshot_binding, MergeAuthorizations::SnapshotBindingV1
    end
  end
end
