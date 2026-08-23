# frozen_string_literal: true

module Coordinator::Write
  class EventSchemaRegistry
    class UnknownSchema < KeyError; end
    class SchemaMismatch < ArgumentError; end

    DEFAULT_DEFINITIONS = {
      [ "ChangeSetCreated", 1 ] => Events::ChangeSetCreatedV1,
      [ "ChangeSetAcceptanceCriteriaDefined", 1 ] => Events::ChangeSetAcceptanceCriteriaDefinedV1,
      [ "CommandCompleted", 1 ] => Events::CommandCompletedV1,
      [ "WorkItemCreated", 1 ] => Events::WorkItemCreatedV1,
      [ "WorkItemAddedToChangeSet", 1 ] => Events::WorkItemAddedToChangeSetV1,
      [ "WorkItemDependencyDeclared", 1 ] => Events::WorkItemDependencyDeclaredV1,
      [ "ChangeSetActivated", 1 ] => Events::ChangeSetActivatedV1,
      [ "WorkItemMadeReady", 1 ] => Events::WorkItemMadeReadyV1,
      [ "WorkItemAcquired", 1 ] => Events::WorkItemAcquiredV1,
      [ "AttemptAuthorized", 1 ] => Events::AttemptAuthorizedV1,
      [ "AttemptStarted", 1 ] => Events::AttemptStartedV1,
      [ "ResourceLeaseAcquired", 1 ] => Events::ResourceLeaseAcquiredV1,
      [ "ResourceLeaseRenewed", 1 ] => Events::ResourceLeaseRenewedV1,
      [ "ResourceLeaseReleased", 1 ] => Events::ResourceLeaseReleasedV1,
      [ "ResourceLeaseExpired", 1 ] => Events::ResourceLeaseExpiredV1,
      [ "WriteSetReserved", 1 ] => Events::WriteSetReservedV1,
      [ "WriteSetExpanded", 1 ] => Events::WriteSetExpandedV1,
      [ "WriteSetRenewed", 1 ] => Events::WriteSetRenewedV1,
      [ "WriteSetReleased", 1 ] => Events::WriteSetReleasedV1,
      [ "UserUtteranceRecorded", 1 ] => Events::UserUtteranceRecordedV1,
      [ "UserUtteranceForwardedByAgent", 1 ] => Events::UserUtteranceForwardedByAgentV1,
      [ "DecisionInterpretationProposed", 1 ] => Events::DecisionInterpretationProposedV1,
      [ "DecisionClarificationRequired", 1 ] => Events::DecisionClarificationRequiredV1,
      [ "DecisionInterpretationAccepted", 1 ] => Events::DecisionInterpretationAcceptedV1,
      [ "DecisionInterpretationRejected", 1 ] => Events::DecisionInterpretationRejectedV1,
      [ "DecisionRecorded", 1 ] => Events::DecisionRecordedV1,
      [ "DecisionActivated", 1 ] => Events::DecisionActivatedV1,
      [ "DecisionDefinitionCorrected", 1 ] => Events::DecisionDefinitionCorrectedV1,
      [ "DecisionSlotOpened", 1 ] => Events::DecisionSlotOpenedV1,
      [ "DecisionSlotHeadChanged", 1 ] => Events::DecisionSlotHeadChangedV1,
      [ "DecisionPartitionAdvanced", 1 ] => Events::DecisionPartitionAdvancedV1,
      [ "AgentChoiceRecorded", 1 ] => Events::AgentChoiceRecordedV1,
      [ "AgentChoiceAccepted", 1 ] => Events::AgentChoiceAcceptedV1,
      [ "AgentChoiceImpactScanStarted", 1 ] => Events::AgentChoiceImpactScanStartedV1,
      [ "AgentChoiceImpactScanSkipped", 1 ] => Events::AgentChoiceImpactScanSkippedV1,
      [ "AgentChoiceImpactScanProgressed", 1 ] => Events::AgentChoiceImpactScanProgressedV1,
      [ "AgentChoiceImpactScanCompleted", 1 ] => Events::AgentChoiceImpactScanCompletedV1,
      [ "AgentChoiceImpactAssessed", 1 ] => Events::AgentChoiceImpactAssessedV1,
      [ "AgentChoiceInvalidatedByDecision", 1 ] => Events::AgentChoiceInvalidatedByDecisionV1,
      [ "CandidateSubmitted", 1 ] => Events::CandidateSubmittedV1,
      [ "CandidateChangeManifestCaptured", 1 ] => Events::CandidateChangeManifestCapturedV1,
      [ "CandidateBuildContextCaptured", 1 ] => Events::CandidateBuildContextCapturedV1,
      [ "CandidateImpactSurfaceDerived", 1 ] => Events::CandidateImpactSurfaceDerivedV1,
      [ "CandidateHeadRegistered", 1 ] => Events::CandidateHeadRegisteredV1,
      [ "CandidateAttachedToAttempt", 1 ] => Events::CandidateAttachedToAttemptV1,
      [ "CoordinationTaskSubmitted", 1 ] => Events::CoordinationTaskSubmittedV1,
      [ "CoordinationTaskExecutionStarted", 1 ] => Events::CoordinationTaskExecutionStartedV1,
      [ "CoordinationTaskCompleted", 1 ] => Events::CoordinationTaskCompletedV1,
      [ "CoordinationTaskFailed", 1 ] => Events::CoordinationTaskFailedV1,
      [ "CoordinationTaskCancellationRequested", 1 ] => Events::CoordinationTaskCancellationRequestedV1,
      [ "CoordinationTaskCancelled", 1 ] => Events::CoordinationTaskCancelledV1
    }.freeze

    DEFAULT_VALIDATORS = {
      Events::CoordinationTaskSubmittedV1 => Contracts::CoordinationTaskSubmission.new
    }.freeze

    def initialize(definitions: DEFAULT_DEFINITIONS, validators: DEFAULT_VALIDATORS)
      @definitions = definitions.dup.freeze
      @validators = validators.dup.freeze
    end

    def fetch(type:, schema_version:)
      @definitions.fetch([ type, schema_version ]) do
        raise UnknownSchema, "unknown event schema: #{type}@#{schema_version}"
      end
    end

    def verify!(event)
      fetch(type: event.class.event_type, schema_version: event.class.schema_version)
      validate!(event)
      event
    end

    def load(type:, schema_version:, data:)
      payload_class = fetch(type:, schema_version:)
      payload = payload_class.new(deep_symbolize(data))
      validate!(payload)
      payload
    end

    private

    def validate!(event)
      validator = @validators[event.class]
      return unless validator

      result = validator.call(event:)
      raise InvalidCoordinationTaskSubmission, result.errors.to_h.inspect if result.failure?
    end

    def deep_symbolize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), output|
          symbol_key = key.to_sym
          raise SchemaMismatch, "duplicate payload key: #{symbol_key.inspect}" if output.key?(symbol_key)

          output[symbol_key] = deep_symbolize(nested)
        end
      when Array
        value.map { deep_symbolize(_1) }
      else
        value
      end
    end
  end
end
