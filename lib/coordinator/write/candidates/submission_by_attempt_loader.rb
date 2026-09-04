# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class SubmissionByAttemptLoader
      def initialize(event_store:, state_loader: StateLoader.new(event_store:))
        @event_store = event_store
        @state_loader = state_loader
      end

      def call(attempt_id)
        submitted = @event_store.read_latest_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentIntegration",
            stream_name: "Candidate",
            event_types: [ "CandidateSubmitted" ],
            markers: [ "attempt:#{attempt_id}" ],
            maximum_count: 1,
            direction: :desc
          )
        )
        return unless submitted

        candidate = @state_loader.call(submitted.stream.stream_id)
        unless candidate && candidate.attempt_id == attempt_id &&
               candidate.submission_event.event_id == submitted.id
          raise InvalidHistory, "Candidate submission does not match its Attempt index"
        end

        candidate
      end
    end
  end
end
