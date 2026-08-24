# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class ExpectedImpactPolicyV1 < Value
      attribute :partition_event, EventReference
      attribute :head, Decisions::DecisionHeadV1
      attribute :definition_digest, Types::Sha256Digest
    end
  end
end
