# frozen_string_literal: true

module Coordinator::Write
  class AgentChoiceImpactScanProgressInvocation < Value
    attribute :command, Types.Instance(Commands::ProgressAgentChoiceImpactScan)
    attribute :checkpoint_event, Types.Instance(PgEventstore::Event)
    attribute :checkpoint_reference, EventReference
  end
end
