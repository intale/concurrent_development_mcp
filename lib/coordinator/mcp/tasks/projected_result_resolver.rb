# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class ProjectedResultResolver
      include Dry::Monads[:result]

      def initialize(receipts: Coordinator::Read::Repositories::CommandReceipts.new)
        @receipts = receipts
      end

      def call(state)
        result = @receipts.fetch(state.command_id)
        return unless result

        result.semantic_result
      end
    end
  end
end
