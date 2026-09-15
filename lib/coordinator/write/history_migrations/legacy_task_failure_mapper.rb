# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyTaskFailureMapper
      CODES = {
        -32_700 => "parse_error",
        -32_600 => "invalid_request",
        -32_601 => "method_not_found",
        -32_602 => "invalid_params",
        -32_603 => "internal_error"
      }.freeze

      def code(value)
        CODES.fetch(value) { "json_rpc_error_#{value.abs}" }
      end
    end
  end
end
