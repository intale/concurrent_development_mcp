# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationValidityScans
    class ScanSnapshot < Value
      attribute :state, Types.Instance(Domain::VerificationObligationValidityScans::State)
      attribute :latest_revision, Types::StreamRevision.optional
      attribute :persisted_events, Types::Array.of(Types.Instance(PgEventstore::Event)).constrained(max_size: 3)
    end
  end
end
