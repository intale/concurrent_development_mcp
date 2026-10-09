# frozen_string_literal: true

module Coordinator::Processes
  class WorkIntentionExpiryRescheduleV1 < Value
    attribute :reschedule_at, Types::Timestamp
  end
end
