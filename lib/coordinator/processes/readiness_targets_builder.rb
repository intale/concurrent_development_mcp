# frozen_string_literal: true

module Coordinator::Processes
  class ReadinessTargetsBuilder
    def initialize(contract: Contracts::ReadinessTargets.new)
      @contract = contract
    end

    def call(source:, memberships:)
      work_item_ids = memberships.map(&:work_item_id)
      result = @contract.call(
        change_set_id: source.payload.change_set_id,
        membership_change_set_ids: memberships.map(&:change_set_id),
        work_item_ids:
      )
      raise InvalidReadinessTargets, result.errors.to_h.inspect if result.failure?

      ReadinessTargets.new(work_item_ids:)
    end
  end
end
