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
          Tools::SkillGet,
          Tools::SkillList,
          Tools::SkillAssetGet,
          Tools::DevelopmentArtifactGet,
          Tools::DevelopmentArtifactContentGet,
          Tools::DevelopmentArtifactList,
          Tools::OperationBatchGet,
          Tools::VerificationObligationsList,
          Tools::MergeSnapshotGet,
          Tools::ChangeSetCreate,
          Tools::WorkItemCreate,
          Tools::WorkItemDependencyDeclare,
          Tools::ChangeSetActivate,
          Tools::WorkItemAcquire,
          Tools::WorkItemComplete,
          Tools::AttemptAbandon,
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
          Tools::CandidateImpactSurfaceSubmit,
          Tools::VerificationObligationClaim,
          Tools::CompatibilityAssessmentSubmit,
          Tools::VerificationObligationWaive,
          Tools::MergeSnapshotRegister,
          Tools::MergeVerificationSubmit,
          Tools::MergeAuthorizationRequest,
          Tools::MergeObservationRecord,
          Tools::ReleaseSetGet,
          Tools::ReleaseSetPrepare,
          Tools::ReleaseRepositoryIntegrationRecord,
          Tools::ReleaseVerificationRecord,
          Tools::ReleaseActivationRecord,
          Tools::ReleaseCompensationComplete,
          Tools::SkillPublish,
          Tools::SkillPublishBatch,
          Tools::DevelopmentArtifactCapture,
          Tools::DevelopmentArtifactCaptureBatch,
          Tools::DevelopmentArtifactRelationDeclare,
          Tools::DevelopmentArtifactRelationDeclareBatch,
          Tools::OperationBatchCancel
        ].freeze
      end
    end
  end
end
