# frozen_string_literal: true

module Coordinator::Processes
  module CandidateObligations
    class PageReader
      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        contract: Contracts::CandidateImpactRevisionPage.new
      )
        @event_store = event_store
        @contract = contract
      end

      def registry(checkpoint)
        state = checkpoint.state
        rows = assignment_page(state)
        page(rows, rows, state)
      end

      def pair(checkpoint)
        state = checkpoint.state
        rows = assignment_page(state)
        registrations = rows.first(state.page_size).select do |event|
          (event.markers & state.markers).any?
        end
        page(rows, registrations, state)
      end

      private

      def assignment_page(state)
        @event_store.read_global_marked_page(
          Coordinator::Write::GlobalMarkedEventPageCriteria.new(
            stream_context: "DevelopmentIntegration",
            stream_name: "Candidate",
            event_type: "CandidateImpactSurfaceAssigned",
            markers: [ "change-set:#{state.change_set_id}" ],
            from_position: state.from_revision,
            to_position: state.to_revision,
            page_size: state.page_size,
            direction: :asc
          )
        )
      end

      def page(rows, registrations, state)
        scanned = rows.first(state.page_size)
        result = RevisionPageV1.new(
          registrations:,
          last_processed_revision: scanned.last&.global_position,
          has_more: rows.length > state.page_size
        )
        validation = @contract.call(
          page: result,
          change_set_id: state.change_set_id,
          from_revision: state.from_revision,
          to_revision: state.to_revision,
          page_size: state.page_size
        )
        return result if validation.success?

        raise CandidateObligationProcessRejected,
              "Candidate impact registry page is invalid: #{validation.errors.to_h.inspect}"
      end
    end
  end
end
