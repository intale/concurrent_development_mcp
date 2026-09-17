# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelToolNameMapper
      RENAMES = {
        "write_set_reserve" => "work_intention_set_declare",
        "write_set_expand" => "work_intention_set_expand",
        "lease_renew" => "work_intention_set_renew",
        "lease_release" => "work_intention_set_withdraw"
      }.freeze

      def call(source_tool_name)
        RENAMES.fetch(source_tool_name, source_tool_name)
      end
    end
  end
end
