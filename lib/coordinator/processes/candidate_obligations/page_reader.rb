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
        @stream_factory = stream_factory
        @contract = contract
      end

      def registry(checkpoint)
        state = checkpoint.state
        rows = @event_store.read_stream_page(
          @stream_factory.candidate_impact_registry(state.change_set_id),
          Coordinator::Write::StreamEventPageCriteria.new(
            event_type: "CandidateImpactSurfaceRegistered",
            from_revision: state.from_revision,
            to_revision: state.to_revision,
            page_size: state.page_size,
            direction: :asc
          )
        )
        page(rows, state)
      end

      def pair(checkpoint)
        state = checkpoint.state
        rows = @event_store.read_stream_marked_page(
          @stream_factory.candidate_impact_registry(state.change_set_id),
          Coordinator::Write::StreamMarkedEventPageCriteria.new(
            event_type: "CandidateImpactSurfaceRegistered",
            markers: state.markers,
            from_revision: state.from_revision,
            to_revision: state.to_revision,
            page_size: state.page_size,
            direction: :asc
          )
        )
        page(rows, state)
      end

      private

      def page(rows, state)
        registrations = rows.first(state.page_size)
        result = RevisionPageV1.new(
          registrations:,
          last_processed_revision: registrations.last&.stream_revision,
          has_more: rows.length > state.page_size
        )
        validation = @contract.call(
          page: result,
          stream_id: state.change_set_id,
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
