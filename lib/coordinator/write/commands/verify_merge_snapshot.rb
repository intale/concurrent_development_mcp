# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class VerifyMergeSnapshot < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :merge_snapshot_id, Types::Identifier
      attribute :verification_id, Types::UuidV7
      attribute :policy_version, Types::MergeSnapshotVerificationPolicyVersion
    end
  end
end
