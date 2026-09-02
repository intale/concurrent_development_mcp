# frozen_string_literal: true

module Coordinator::Write
  class AgentChoiceImpactScanInvocation < Value
    attribute :command, Types.Instance(Commands::StartAgentChoiceImpactScan)
    attribute :source_event, Types.Instance(PgEventstore::Event)
    attribute :source_reference, EventReference
    attribute :caused_by, Types.Instance(PgEventstore::Event)
  end
end
