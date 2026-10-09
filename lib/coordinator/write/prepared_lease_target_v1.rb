# frozen_string_literal: true

module Coordinator::Write
  class PreparedLeaseTargetV1 < Value
    attribute :target, Types.Instance(WorkIntentionTargetV1)
    attribute :lease_id, Types::UuidV7
    attribute :event_id, Types::UuidV7
  end
end
