# frozen_string_literal: true

module Coordinator::Shared
  module Subscriptions
    class Identity < Value
      attribute :set_name, Types::Identifier
      attribute :subscription_name, Types::Identifier
    end
  end
end
