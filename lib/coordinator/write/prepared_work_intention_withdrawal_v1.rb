# frozen_string_literal: true

module Coordinator::Write
  class PreparedWorkIntentionWithdrawalV1 < Value
    attribute :reference, Types.Instance(WorkIntentionFencedReferenceV1)
    attribute :event_id, Types::UuidV7
  end
end
