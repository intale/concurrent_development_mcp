# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RecordReleaseSetActivation < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :release_set_id, Types::Identifier
      attribute :verification_event, EventReference
      attribute :verification_digest, Types::Sha256Digest
      attribute :activation_point, ReleaseSets::ActivationPointV1
      attribute :policy_version, Types::ReleaseSetActivationPolicyVersion
    end
  end
end
