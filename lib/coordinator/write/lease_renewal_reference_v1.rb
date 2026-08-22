# frozen_string_literal: true

module Coordinator::Write
  class LeaseRenewalReferenceV1 < Value
    attribute :resource_key_hash, Types::Sha256Digest
    attribute :lease_id, Types::UuidV7
    attribute :fencing_token, Types::FencingToken
  end
end
