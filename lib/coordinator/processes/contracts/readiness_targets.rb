# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class ReadinessTargets < Dry::Validation::Contract
      params do
        required(:source_work_item_count).filled(:integer, gteq?: 1, lteq?: 100)
        required(:work_item_ids).value(Types::ReadinessWorkItemIds)
      end

      rule(:source_work_item_count, :work_item_ids) do
        source_count = values[:source_work_item_count]
        work_item_ids = values[:work_item_ids]

        unless work_item_ids.length == source_count
          key(:work_item_ids).failure("must match the source activation work-item count")
        end
        unless work_item_ids.uniq.length == work_item_ids.length
          key(:work_item_ids).failure("must contain unique authoritative memberships")
        end
      end
    end
  end
end
