# frozen_string_literal: true

module Coordinator
  class ReadinessTargets < Value
    attribute :work_item_ids, Types::ReadinessWorkItemIds
  end
end
