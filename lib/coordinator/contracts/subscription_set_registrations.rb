# frozen_string_literal: true

module Coordinator
  module Contracts
    class SubscriptionSetRegistrations < Dry::Validation::Contract
      params do
        required(:set_name).filled(:string)
        required(:registrations).filled(:array).each(Types.Instance(Subscriptions::Registration))
      end

      rule(:set_name, :registrations) do
        definitions = values[:registrations].map(&:definition)
        foreign_sets = definitions.reject { _1.set_name == values[:set_name] }
        key(:registrations).failure("must all belong to the requested subscription set") if foreign_sets.any?

        names = definitions.map(&:subscription_name)
        key(:registrations).failure("must have unique subscription names") unless names.uniq.length == names.length
      end
    end
  end
end
