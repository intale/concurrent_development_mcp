# frozen_string_literal: true

module Coordinator::Write
  class CandidateImpactPairScanInvocation < Value
    attribute :command, Types.Instance(Commands::StartCandidateImpactPairScan)
    attribute :source_event, Types.Instance(PgEventstore::Event)
    attribute :source_reference, EventReference
  end
end
