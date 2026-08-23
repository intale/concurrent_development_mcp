# frozen_string_literal: true

module Coordinator::Write
  class CandidateImpactRegistrySweepInvocation < Value
    attribute :command, Types.Instance(Commands::StartCandidateImpactRegistrySweep)
    attribute :source_event, Types.Instance(PgEventstore::Event)
    attribute :source_reference, EventReference
  end
end
