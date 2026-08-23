# frozen_string_literal: true

module Coordinator::Processes
  module CandidateObligations
    class RevisionPageV1 < Value
      attribute :registrations,
                Types::Array.of(Types.Instance(PgEventstore::Event)).constrained(max_size: 50)
      attribute :last_processed_revision, Types::StreamRevision.optional
      attribute :has_more, Types::Bool
    end
  end
end
