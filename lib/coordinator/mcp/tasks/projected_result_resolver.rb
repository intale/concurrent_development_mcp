# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    class ProjectedResultResolver
      include Dry::Monads[:result]

      def initialize(
        receipts: Coordinator::Read::Repositories::CommandReceipts.new,
        mapper: Coordinator::Write::Tasks::SemanticResultMapper.new
      )
        @receipts = receipts
        @mapper = mapper
      end

      def call(state)
        completion = @receipts.fetch(state.command_id)
        return unless completion

        @mapper.call(
          Success(completion),
          command_id: state.command_id,
          tool_name: state.tool_name
        )
      end
    end
  end
end
