# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class ActivationDigestDocumentV1 < Value
      attribute :schema, Types::String.enum("release-set-activation/v1")
      attribute :release_set_id, Types::Identifier
      attribute :release_digest, Types::Sha256Digest
      attribute :verification_event, EventReference
      attribute :verification_digest, Types::Sha256Digest
      attribute :activation_point, ActivationPointV2
      attribute :policy_version, Types::ReleaseSetActivationPolicyVersion
    end
  end
end
