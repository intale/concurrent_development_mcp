# frozen_string_literal: true

module Coordinator::Write
  class LeaseReleaseReferenceV2 < Value
    attribute :resource_id, Types::ResourceId
    attribute :lease_id, Types::UuidV7
    attribute :fencing_token, Types::FencingToken
  end
end
