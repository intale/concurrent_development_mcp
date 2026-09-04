# frozen_string_literal: true

module Coordinator::Write
  class PreparedWorkIntentionTargetV1 < Value
    attribute :target, Types.Instance(ResourceLeaseTargetV1)
    attribute :intention_id, Types::UuidV7
    attribute :declaration_event_id, Types::UuidV7
    attribute :membership_event_id, Types::UuidV7
  end
end
