# frozen_string_literal: true

module Coordinator::Write
  class PreparedLeaseResourceV1 < Value
    attribute :resource, Types.Instance(FileResourceV1)
    attribute :lease_id, Types::UuidV7
    attribute :event_id, Types::UuidV7
  end
end
