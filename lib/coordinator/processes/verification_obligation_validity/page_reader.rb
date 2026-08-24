# frozen_string_literal: true

module Coordinator::Processes
  module VerificationObligationValidity
    class PageReader
      def initialize(event_store:, contract: Contracts::VerificationObligationValidityPage.new)
        @event_store = event_store
        @contract = contract
      end

      def call(checkpoint)
        rows = @event_store.read_global_marked_page(
          Coordinator::Write::GlobalMarkedEventPageCriteria.new(
            stream_context: "DevelopmentIntegration",
            stream_name: "VerificationObligation",
            event_type: "VerificationObligationCreated",
            markers: [ "change-set:#{checkpoint.change_set_id}" ],
            from_position: checkpoint.from_position,
            to_position: checkpoint.to_position,
            page_size: checkpoint.page_size,
            direction: :asc
          )
        )
        targets = rows.first(checkpoint.page_size)
        page = PageV1.new(
          obligations: targets,
          last_processed_position: targets.last&.global_position,
          has_more: rows.length > checkpoint.page_size
        )
        result = @contract.call(page:, checkpoint:)
        return page if result.success?

        raise VerificationObligationValidityProcessRejected,
              "Validity scan page is invalid: #{result.errors.to_h.inspect}"
      rescue Dry::Struct::Error => error
        raise VerificationObligationValidityProcessRejected, error.message
      end
    end
  end
end
