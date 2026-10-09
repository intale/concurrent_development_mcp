# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class ReadinessTargets < Dry::Validation::Contract
      params do
        required(:change_set_id).value(Types::Identifier)
        required(:membership_change_set_ids).array(Types::Identifier)
        required(:work_item_ids).value(Types::ReadinessWorkItemIds)
      end

      rule(:work_item_ids) do
        work_item_ids = values[:work_item_ids]
        unless work_item_ids.uniq.length == work_item_ids.length
          key(:work_item_ids).failure("must contain unique authoritative memberships")
        end
      end

      rule(:change_set_id, :membership_change_set_ids, :work_item_ids) do
        memberships = values[:membership_change_set_ids]
        unless memberships.length == values[:work_item_ids].length &&
               memberships.all? { _1 == values[:change_set_id] }
          key(:membership_change_set_ids).failure("must belong to the activated ChangeSet")
        end
      end
    end
  end
end
