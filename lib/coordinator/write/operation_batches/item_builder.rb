# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class ItemBuilder
      def call(event:, payload:)
        submitted_input = payload.input
        command_input = submitted_input.class.new(
          submitted_input.attributes.merge(command_id: payload.command_id)
        )

        ItemV2.new(
          index: payload.index,
          request_id: submitted_input.command_id,
          command_input:,
          canonical_input_digest: event.metadata.fetch("canonical_input_digest")
        )
      end
    end
  end
end
