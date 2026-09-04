# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshots
    class CandidateLoader
      def initialize(
        event_store:,
        state_loader: Candidates::StateLoader.new(event_store:),
        contract: Contracts::MergeSnapshotCandidateHistory.new
      )
        @state_loader = state_loader
        @contract = contract
      end

      def call(requested)
        candidate = @state_loader.call(requested.candidate_id)
        history = CandidateHistoryV1.new(
          requested:,
          candidate:,
          manifest: candidate&.manifest,
          candidate_event: candidate&.submission_event,
          manifest_event: candidate&.manifest_event
        )
        validation = @contract.call(history:)
        return history if validation.success?

        raise InvalidMergeSnapshotCandidateHistory, validation.errors.to_h.inspect
      end
    end
  end
end
