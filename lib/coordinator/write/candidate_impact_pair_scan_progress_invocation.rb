# frozen_string_literal: true

module Coordinator::Write
  class CandidateImpactPairScanProgressInvocation < Value
    attribute :command, Types.Instance(Commands::ProgressCandidateImpactPairScan)
    attribute :checkpoint_event, Types.Instance(PgEventstore::Event)
    attribute :checkpoint_reference, EventReference
  end
end
