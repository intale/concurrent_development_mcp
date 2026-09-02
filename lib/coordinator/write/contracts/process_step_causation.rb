# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    module ProcessStepCausation
      private

      def process_step_matches?(event, command_id:, target_entity_id: nil)
        return false unless event.type == "ProcessStepPlanned"
        return false unless event.stream&.context == "CoordinatorControl"
        return false unless event.stream&.stream_name == "ProcessStep"
        return false if event.stream_revision.nil? || event.global_position.nil?

        data = event.data
        matches = value(data, "target_command_id") == command_id
        matches &&= value(data, "target_entity_id") == target_entity_id if target_entity_id
        matches
      end

      def value(data, key)
        data[key] || data[key.to_sym]
      end
    end
  end
end
