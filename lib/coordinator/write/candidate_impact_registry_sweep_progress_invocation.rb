# frozen_string_literal: true

module Coordinator::Write
  class CandidateImpactRegistrySweepProgressInvocation < Value
    attribute :command, Types.Instance(Commands::ProgressCandidateImpactRegistrySweep)
    attribute :checkpoint_event, Types.Instance(PgEventstore::Event)
    attribute :checkpoint_reference, EventReference
  end
end
