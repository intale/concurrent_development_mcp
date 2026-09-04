# frozen_string_literal: true

module Coordinator::Processes
  class ReadinessTargetsBuilder
    def initialize(contract: Contracts::ReadinessTargets.new)
      @contract = contract
    end

    def call(source:, memberships:)
      work_item_ids = memberships.map(&:work_item_id)
      result = @contract.call(
        source_work_item_count: source_work_item_count(source, work_item_ids),
        work_item_ids:
      )
      raise InvalidReadinessTargets, result.errors.to_h.inspect if result.failure?

      ReadinessTargets.new(work_item_ids:)
    end

    private

    def source_work_item_count(source, work_item_ids)
      return source.payload.work_item_count if source.payload.respond_to?(:work_item_count)

      work_item_ids.length
    end
  end
end
