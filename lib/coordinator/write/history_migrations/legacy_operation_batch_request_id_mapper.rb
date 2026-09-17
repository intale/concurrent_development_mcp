# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyOperationBatchRequestIdMapper
      def initialize(public_mapper: LegacyRequestIdMapper.new)
        @public_mapper = public_mapper
      end

      def call(command_id:, source_position:, item_index:, command_history_present:)
        return @public_mapper.call(command_id:, source_position:) if command_history_present
        return command_id if Types::PublicCommandId.valid?(command_id)

        "legacy-batch:#{source_position}:#{item_index}"
      end
    end
  end
end
