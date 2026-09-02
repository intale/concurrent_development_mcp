# frozen_string_literal: true

module Coordinator::Write
  class AgentChoiceImpactScanProgressInvocation < Value
    attribute :command, Types.Instance(Commands::ProgressAgentChoiceImpactScan)
    attribute :checkpoint_event, Types.Instance(PgEventstore::Event)
    attribute :checkpoint_reference, EventReference
    attribute :caused_by, Types.Instance(PgEventstore::Event)
  end
end
