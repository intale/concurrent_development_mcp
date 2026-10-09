# frozen_string_literal: true

module Coordinator::Processes
  class WorkIntentionExpiryHandledV1 < Value
    attribute :outcome, Types::String.enum("expired_or_replayed")
  end
end
