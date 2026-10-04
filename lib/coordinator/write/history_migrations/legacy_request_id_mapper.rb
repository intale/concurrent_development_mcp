# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyRequestIdMapper
      def call(command_id:, source_position:)
        return command_id if Types::PublicCommandId.valid?(command_id)

        "historical-request:#{source_position}"
      end
    end
  end
end
