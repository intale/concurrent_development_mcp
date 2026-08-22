# frozen_string_literal: true

module Coordinator::Shared
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

        identities = definitions.map(&:identity)
        unless identities.uniq.length == identities.length
          key(:registrations).failure("must have unique subscription-set/name identities")
        end
      end
    end
  end
end
