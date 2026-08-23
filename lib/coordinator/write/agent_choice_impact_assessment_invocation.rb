# frozen_string_literal: true

module Coordinator::Write
  class AgentChoiceImpactAssessmentInvocation < Value
    attribute :command, Types.Instance(Commands::AssessAgentChoiceDecisionImpact)
    attribute :caused_by, Types.Instance(PgEventstore::Event)
    attribute :caused_by_reference, EventReference
  end
end
