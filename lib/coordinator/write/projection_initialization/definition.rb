# frozen_string_literal: true

module Coordinator::Write
  module ProjectionInitialization
    class Definition < Value
      attribute :context, Types::Identifier
      attribute :stream_name, Types::Identifier
      attribute :source_type, Types::Identifier
      attribute :target_types, Types::Array.of(Types::Identifier)
      attribute :history_types, Types::Array.of(Types::Identifier)
      attribute :history_maximum_count, Types::Integer.optional

      def matches?(reference)
        context == reference.stream_context && stream_name == reference.stream_name && source_type == reference.type
      end

      ALL = [
        new(context: "DevelopmentCoordination", stream_name: "OperationBatch", source_type: "OperationBatchCreated",
          target_types: %w[OperationBatchManifestAccepted OperationBatchSucceededItemsNumberChanged OperationBatchUnsuccessfulItemsNumberChanged OperationBatchOutcomeRecorded],
          history_types: %w[OperationBatchItemEnqueued OperationBatchItemSucceeded OperationBatchItemRejected OperationBatchItemRegistrationRejected OperationBatchItemFailed OperationBatchCompleted OperationBatchCancelled],
          history_maximum_count: 2 * Types::OPERATION_BATCH_MAXIMUM_ITEMS + 1),
        new(context: "DevelopmentIntegration", stream_name: "VerificationObligation", source_type: "VerificationObligationCreated",
          target_types: %w[VerificationObligationEvidenceNumberChanged VerificationObligationEvidenceCoverageChanged],
          history_types: %w[VerificationEvidenceSubmitted], history_maximum_count: Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT),
        new(context: "HumanGuidance", stream_name: "Decision", source_type: "DecisionActivated",
          target_types: %w[DecisionCorrectionsNumberChanged], history_types: %w[DecisionDefinitionCorrected], history_maximum_count: nil),
        new(context: "AgentKnowledge", stream_name: "SkillRevision", source_type: "SkillRevisionCreated",
          target_types: %w[SkillRevisionRepresentationRecorded], history_types: %w[SkillAssetAddedToRevision],
          history_maximum_count: Types::SKILL_ASSET_MAXIMUM_COUNT),
        new(context: "DevelopmentIntegration", stream_name: "ReleaseSet", source_type: "ReleaseSetPrepared",
          target_types: %w[ReleaseSetVerificationRequested],
          history_types: %w[ReleaseSetMemberAdded RepositoryIntegrationRecorded RepositoryIntegrationMergeLinked ReleaseSetActivated ReleaseSetCompensationRequested ReleaseSetCompleted],
          history_maximum_count: Types::RELEASE_SET_MAXIMUM_MEMBERS * (1 + 2 * Types::RELEASE_SET_INTEGRATION_MAXIMUM_ATTEMPTS) + 3)
      ].freeze

      def self.for_source(reference)
        ALL.find { _1.matches?(reference) }
      end
    end
  end
end
