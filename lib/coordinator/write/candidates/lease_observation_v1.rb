# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class LeaseObservationV1 < Value
      attribute :resource_id, Types::ResourceId
      attribute :lease_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
    end
  end
end
