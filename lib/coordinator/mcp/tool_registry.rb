# frozen_string_literal: true

module Coordinator
  module Mcp
    module ToolRegistry
      module_function

      def all
        [
          Tools::CoordContext,
          Tools::OperationGet,
          Tools::GuidanceGet,
          Tools::DecisionInterpretationList,
          Tools::DecisionGet,
          Tools::DecisionResolve,
          Tools::AgentChoiceGet,
          Tools::AgentChoiceImpactList,
          Tools::CandidateGet,
          Tools::CandidateList,
          Tools::CandidateImpactGet,
          Tools::VerificationObligationsList,
          Tools::ChangeSetCreate,
          Tools::WorkItemCreate,
          Tools::WorkItemDependencyDeclare,
          Tools::ChangeSetActivate,
          Tools::WorkItemAcquire,
          Tools::WriteSetReserve,
          Tools::WriteSetExpand,
          Tools::LeaseRenew,
          Tools::LeaseRelease,
          Tools::GuidanceRecord,
          Tools::DecisionInterpretationPropose,
          Tools::DecisionInterpretationAdjudicate,
          Tools::DecisionActivate,
          Tools::DecisionCorrect,
          Tools::AgentChoiceRecord,
          Tools::CandidateSubmit,
          Tools::CandidateImpactSurfaceSubmit
        ].freeze
      end
    end
  end
end
