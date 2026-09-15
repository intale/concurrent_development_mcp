# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CommandInputRebinder
      def initialize(
        target_command_builder: Tasks::TargetCommandBuilder.new,
        input_digest: CommandInputDigest.new
      )
        @target_command_builder = target_command_builder
        @input_digest = input_digest
      end

      def call(document:, command_id:)
        rebound = document.class.new(document.to_h.merge(command_id:))
        command = @target_command_builder.call(rebound)
        MigratedCommandInputV1.new(
          document: rebound,
          canonical_input_digest: @input_digest.request(command)
        )
      end
    end
  end
end
