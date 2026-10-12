# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class WorkIntentionRenewalGet < Dry::Validation::Contract
      params do
        optional(:renewal_id).filled(Types::UuidV7)
        optional(:task_id).filled(Types::UuidV7)
      end

      rule do
        base.failure("provide exactly one renewal_id or task_id") unless [ values[:renewal_id], values[:task_id] ].compact.one?
      end
    end
  end
end
