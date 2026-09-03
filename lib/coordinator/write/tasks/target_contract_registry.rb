# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class TargetContractV1 < Dry::Struct
      schema schema.strict
      ClassType = Types.Instance(::Class)

      attribute :tool_name, Types::Identifier
      attribute :input_document_class, ClassType
      attribute :command_class, ClassType
      attribute :receipt_class, ClassType

      def input_document_type
        Types.Instance(input_document_class)
      end

      def command_type
        Types.Instance(command_class)
      end

      def receipt_type
        Types.Instance(receipt_class)
      end

      def builder_method
        :"build_#{command_class.name.demodulize.underscore}"
      end

      def executor_variable
        :"@#{command_class.name.demodulize.underscore}"
      end
    end

    module TargetContractRegistry
      CONTRACTS = [
        TargetContractV1.new(
          tool_name: "repository_register",
          input_document_class: CommandInputDocuments::RegisterRepositoryV1,
          command_class: Commands::RegisterRepository,
          receipt_class: CommandReceiptData::RepositoryRegistration
        ),
        TargetContractV1.new(
          tool_name: "resource_resolve",
          input_document_class: CommandInputDocuments::ResolveResourceV1,
          command_class: Commands::ResolveResource,
          receipt_class: CommandReceiptData::ResourceResolution
        ),
        TargetContractV1.new(
          tool_name: "resource_remove",
          input_document_class: CommandInputDocuments::RemoveResourceV1,
          command_class: Commands::RemoveResource,
          receipt_class: CommandReceiptData::ResourceRemoval
        ),
        TargetContractV1.new(
          tool_name: "change_set_create",
          input_document_class: CommandInputDocuments::CreateChangeSetV1,
          command_class: Commands::CreateChangeSet,
          receipt_class: CommandReceiptData::ChangeSet
        ),
        TargetContractV1.new(
          tool_name: "work_item_create",
          input_document_class: CommandInputDocuments::CreateWorkItemV1,
          command_class: Commands::CreateWorkItem,
          receipt_class: CommandReceiptData::WorkItem
        ),
        TargetContractV1.new(
          tool_name: "work_item_dependency_declare",
          input_document_class: CommandInputDocuments::DeclareWorkItemDependencyV1,
          command_class: Commands::DeclareWorkItemDependency,
          receipt_class: CommandReceiptData::Dependency
        ),
        TargetContractV1.new(
          tool_name: "change_set_activate",
          input_document_class: CommandInputDocuments::ActivateChangeSetV1,
          command_class: Commands::ActivateChangeSet,
          receipt_class: CommandReceiptData::ChangeSet
        ),
        TargetContractV1.new(
          tool_name: "work_item_acquire",
          input_document_class: CommandInputDocuments::AcquireWorkItemV1,
          command_class: Commands::AcquireWorkItem,
          receipt_class: CommandReceiptData::Attempt
        ),
        TargetContractV1.new(
          tool_name: "work_item_complete",
          input_document_class: CommandInputDocuments::CompleteWorkItemV1,
          command_class: Commands::CompleteWorkItem,
          receipt_class: CommandReceiptData::WorkItemCompletion
        ),
        TargetContractV1.new(
          tool_name: "attempt_abandon",
          input_document_class: CommandInputDocuments::AbandonAttemptV1,
          command_class: Commands::AbandonAttempt,
          receipt_class: CommandReceiptData::Attempt
        ),
        TargetContractV1.new(
          tool_name: "write_set_reserve",
          input_document_class: CommandInputDocuments::ReserveWriteSetV1,
          command_class: Commands::ReserveWriteSet,
          receipt_class: CommandReceiptData::LeaseSet
        ),
        TargetContractV1.new(
          tool_name: "write_set_expand",
          input_document_class: CommandInputDocuments::ExpandWriteSetV1,
          command_class: Commands::ExpandWriteSet,
          receipt_class: CommandReceiptData::LeaseSetExpansion
        ),
        TargetContractV1.new(
          tool_name: "lease_renew",
          input_document_class: CommandInputDocuments::RenewLeaseSetV1,
          command_class: Commands::RenewLeaseSet,
          receipt_class: CommandReceiptData::LeaseSetRenewal
        ),
        TargetContractV1.new(
          tool_name: "lease_release",
          input_document_class: CommandInputDocuments::ReleaseLeaseSetV1,
          command_class: Commands::ReleaseLeaseSet,
          receipt_class: CommandReceiptData::LeaseSetRelease
        ),
        TargetContractV1.new(
          tool_name: "guidance_record",
          input_document_class: CommandInputDocuments::RecordGuidanceV1,
          command_class: Commands::RecordGuidance,
          receipt_class: CommandReceiptData::Guidance
        ),
        TargetContractV1.new(
          tool_name: "decision_interpretation_propose",
          input_document_class: CommandInputDocuments::ProposeDecisionInterpretationV1,
          command_class: Commands::ProposeDecisionInterpretation,
          receipt_class: CommandReceiptData::InterpretationProposal
        ),
        TargetContractV1.new(
          tool_name: "decision_interpretation_adjudicate",
          input_document_class: CommandInputDocuments::AdjudicateDecisionInterpretationV1,
          command_class: Commands::AdjudicateDecisionInterpretation,
          receipt_class: CommandReceiptData::InterpretationAdjudication
        ),
        TargetContractV1.new(
          tool_name: "decision_activate",
          input_document_class: CommandInputDocuments::ActivateDecisionV1,
          command_class: Commands::ActivateDecision,
          receipt_class: CommandReceiptData::DecisionActivation
        ),
        TargetContractV1.new(
          tool_name: "decision_correct",
          input_document_class: CommandInputDocuments::CorrectDecisionV1,
          command_class: Commands::CorrectDecision,
          receipt_class: CommandReceiptData::DecisionCorrection
        ),
        TargetContractV1.new(
          tool_name: "agent_choice_record",
          input_document_class: CommandInputDocuments::RecordAgentChoiceV1,
          command_class: Commands::RecordAgentChoice,
          receipt_class: CommandReceiptData::AgentChoice
        ),
        TargetContractV1.new(
          tool_name: "candidate_submit",
          input_document_class: CommandInputDocuments::SubmitCandidateV1,
          command_class: Commands::SubmitCandidate,
          receipt_class: CommandReceiptData::CandidateSubmission
        ),
        TargetContractV1.new(
          tool_name: "candidate_impact_surface_submit",
          input_document_class: CommandInputDocuments::SubmitCandidateImpactSurfaceV1,
          command_class: Commands::SubmitCandidateImpactSurface,
          receipt_class: CommandReceiptData::CandidateImpactSurface
        ),
        TargetContractV1.new(
          tool_name: "verification_obligation_claim",
          input_document_class: CommandInputDocuments::ClaimVerificationObligationV1,
          command_class: Commands::ClaimVerificationObligation,
          receipt_class: CommandReceiptData::VerificationObligationClaim
        ),
        TargetContractV1.new(
          tool_name: "compatibility_assessment_submit",
          input_document_class: CommandInputDocuments::SubmitCompatibilityAssessmentV1,
          command_class: Commands::SubmitCompatibilityAssessment,
          receipt_class: CommandReceiptData::CompatibilityAssessment
        ),
        TargetContractV1.new(
          tool_name: "verification_obligation_waive",
          input_document_class: CommandInputDocuments::WaiveVerificationObligationV1,
          command_class: Commands::WaiveVerificationObligation,
          receipt_class: CommandReceiptData::VerificationObligationWaiver
        ),
        TargetContractV1.new(
          tool_name: "merge_snapshot_register",
          input_document_class: CommandInputDocuments::RegisterMergeSnapshotV1,
          command_class: Commands::RegisterMergeSnapshot,
          receipt_class: CommandReceiptData::MergeSnapshotRegistration
        ),
        TargetContractV1.new(
          tool_name: "merge_verification_submit",
          input_document_class: CommandInputDocuments::SubmitMergeSnapshotVerificationV1,
          command_class: Commands::SubmitMergeSnapshotVerification,
          receipt_class: CommandReceiptData::MergeSnapshotVerification
        ),
        TargetContractV1.new(
          tool_name: "merge_authorization_request",
          input_document_class: CommandInputDocuments::RequestMergeAuthorizationV1,
          command_class: Commands::RequestMergeAuthorization,
          receipt_class: CommandReceiptData::MergeAuthorization
        ),
        TargetContractV1.new(
          tool_name: "merge_observation_record",
          input_document_class: CommandInputDocuments::RecordMergeObservationV1,
          command_class: Commands::RecordMergeObservation,
          receipt_class: CommandReceiptData::MergeObservation
        ),
        TargetContractV1.new(
          tool_name: "release_set_prepare",
          input_document_class: CommandInputDocuments::PrepareReleaseSetV1,
          command_class: Commands::PrepareReleaseSet,
          receipt_class: CommandReceiptData::ReleaseSetPreparation
        ),
        TargetContractV1.new(
          tool_name: "release_repository_integration_record",
          input_document_class: CommandInputDocuments::RecordRepositoryIntegrationV1,
          command_class: Commands::RecordRepositoryIntegration,
          receipt_class: CommandReceiptData::RepositoryIntegration
        ),
        TargetContractV1.new(
          tool_name: "release_verification_record",
          input_document_class: CommandInputDocuments::RecordReleaseSetVerificationV1,
          command_class: Commands::RecordReleaseSetVerification,
          receipt_class: CommandReceiptData::ReleaseSetVerification
        ),
        TargetContractV1.new(
          tool_name: "release_activation_record",
          input_document_class: CommandInputDocuments::RecordReleaseSetActivationV1,
          command_class: Commands::RecordReleaseSetActivation,
          receipt_class: CommandReceiptData::ReleaseSetActivation
        ),
        TargetContractV1.new(
          tool_name: "release_compensation_complete",
          input_document_class: CommandInputDocuments::CompleteCompensatedReleaseSetV1,
          command_class: Commands::CompleteCompensatedReleaseSet,
          receipt_class: CommandReceiptData::ReleaseSetCompletion
        ),
        TargetContractV1.new(
          tool_name: "skill_publish",
          input_document_class: CommandInputDocuments::PublishSkillRevisionBase,
          command_class: Commands::PublishSkillRevision,
          receipt_class: CommandReceiptData::SkillPublication
        ),
        TargetContractV1.new(
          tool_name: "skill_publish_batch",
          input_document_class: CommandInputDocuments::CreateOperationBatchV1,
          command_class: Commands::CreateOperationBatch,
          receipt_class: CommandReceiptData::OperationBatchAcceptance
        ),
        TargetContractV1.new(
          tool_name: "development_artifact_capture",
          input_document_class: CommandInputDocuments::CaptureDevelopmentArtifactBase,
          command_class: Commands::CaptureDevelopmentArtifact,
          receipt_class: CommandReceiptData::DevelopmentArtifactCapture
        ),
        TargetContractV1.new(
          tool_name: "development_artifact_capture_batch",
          input_document_class: CommandInputDocuments::CreateOperationBatchV1,
          command_class: Commands::CreateOperationBatch,
          receipt_class: CommandReceiptData::OperationBatchAcceptance
        ),
        TargetContractV1.new(
          tool_name: "development_artifact_update",
          input_document_class: CommandInputDocuments::UpdateDevelopmentArtifactV1,
          command_class: Commands::UpdateDevelopmentArtifact,
          receipt_class: CommandReceiptData::DevelopmentArtifactUpdate
        ),
        TargetContractV1.new(
          tool_name: "development_artifact_classification_correct",
          input_document_class: CommandInputDocuments::CorrectDevelopmentArtifactClassificationV1,
          command_class: Commands::CorrectDevelopmentArtifactClassification,
          receipt_class: CommandReceiptData::DevelopmentArtifactClassification
        ),
        TargetContractV1.new(
          tool_name: "development_artifact_relation_declare",
          input_document_class: CommandInputDocuments::DeclareDevelopmentArtifactRelationV1,
          command_class: Commands::DeclareDevelopmentArtifactRelation,
          receipt_class: CommandReceiptData::DevelopmentArtifactRelation
        ),
        TargetContractV1.new(
          tool_name: "development_artifact_relation_declare_batch",
          input_document_class: CommandInputDocuments::CreateOperationBatchV1,
          command_class: Commands::CreateOperationBatch,
          receipt_class: CommandReceiptData::OperationBatchAcceptance
        ),
        TargetContractV1.new(
          tool_name: "operation_batch_cancel",
          input_document_class: CommandInputDocuments::CancelOperationBatchV1,
          command_class: Commands::CancelOperationBatch,
          receipt_class: CommandReceiptData::OperationBatchCancellation
        )
      ].each(&:freeze).freeze

      BY_TOOL_NAME = CONTRACTS.to_h { [ _1.tool_name, _1 ] }.freeze
      BY_COMMAND_CLASS = CONTRACTS.to_h { [ _1.command_class, _1 ] }.freeze

      module_function

      def fetch(tool_name)
        BY_TOOL_NAME.fetch(tool_name)
      end

      def tool_names
        BY_TOOL_NAME.keys
      end

      def fetch_by_command_class(command_class)
        BY_COMMAND_CLASS.fetch(command_class)
      end

      def fetch_for(command)
        if command.is_a?(Commands::CreateOperationBatch)
          return fetch("#{command.target_tool}_batch")
        end

        fetch_by_command_class(command.class)
      end

      def input_document_classes
        accepted_classes = CONTRACTS.map(&:input_document_class)

        CommandInputDocuments::TARGET_TYPES.select do |document_class|
          accepted_classes.any? { document_class <= _1 }
        end.freeze
      end

      def command_classes
        CONTRACTS.map(&:command_class).uniq.freeze
      end
    end
  end
end
