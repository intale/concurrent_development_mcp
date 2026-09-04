# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class ActivationFactV2 < Value
      attribute :payload, Events::ReleaseSetActivatedV2
      attribute :event, EventReference
      attribute :activation_digest, Types::Sha256Digest
      attribute :release_digest, Types::Sha256Digest
      attribute :verification_digest, Types::Sha256Digest
      attribute :policy_version, Types::ReleaseSetActivationPolicyVersion
    end
  end
end
