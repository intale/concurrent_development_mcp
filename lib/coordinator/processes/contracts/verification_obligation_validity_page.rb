# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class VerificationObligationValidityPage < Dry::Validation::Contract
      params do
        required(:page).value(Types.Instance(VerificationObligationValidity::PageV1))
        required(:checkpoint).value(Types.Instance(VerificationObligationValidity::ScanCheckpointV1))
      end

      rule(:page, :checkpoint) do
        page = values[:page]
        checkpoint = values[:checkpoint]
        positions = page.obligations.map(&:global_position)
        valid = positions == positions.sort && positions.uniq.length == positions.length &&
          positions.all? { _1.between?(checkpoint.from_position, checkpoint.to_position) } &&
          page.last_processed_position == positions.last &&
          (!page.has_more || page.obligations.length == checkpoint.page_size) &&
          page.obligations.all? { valid_obligation?(_1, checkpoint.change_set_id) }
        key(:page).failure("must be a bounded ascending page of matching obligation creations") unless valid
      end

      private

      def valid_obligation?(event, change_set_id)
        event.type == "VerificationObligationCreated" &&
          event.stream.context == "DevelopmentIntegration" &&
          event.stream.stream_name == "VerificationObligation" &&
          event.stream_revision.zero? &&
          event.markers.include?("change-set:#{change_set_id}")
      end
    end
  end
end
