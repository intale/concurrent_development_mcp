# frozen_string_literal: true

module Coordinator::Write
  module CommandReceiptData
    class ChangeSet < Value
      attribute :change_set_id, Types::Identifier
    end

    class WorkItem < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
    end

    class Dependency < Value
      attribute :change_set_id, Types::Identifier
      attribute :dependency_id, Types::Identifier
    end

    class Attempt < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
    end

    class LeaseSet < Value
      Reference = LeaseReferenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :lease_set_id, Types::UuidV7
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
      attribute :acquired_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
      attribute :resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
    end

    class LeaseSetExpansion < Value
      Reference = LeaseReferenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :lease_set_id, Types::UuidV7
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
      attribute :expanded_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
      attribute :added_resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 31)
      attribute :resource_count, Types::ExpandedWriteSetSize
    end

    class LeaseSetRenewal < Value
      Reference = LeaseReferenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :lease_set_id, Types::UuidV7
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
      attribute :resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
      attribute :resource_count, Types::WriteSetSize
      attribute :renewed_at, Types::Timestamp
      attribute :previous_expires_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
    end

    class LeaseSetRelease < Value
      Reference = LeaseReferenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :lease_set_id, Types::UuidV7
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
      attribute :resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
      attribute :resource_count, Types::WriteSetSize
      attribute :previous_expires_at, Types::Timestamp
      attribute :released_at, Types::Timestamp
    end

    class ResourceLeaseExpiry < Value
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :lease_id, Types::UuidV7
      attribute :lease_set_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
      attribute :expires_at, Types::Timestamp
      attribute :expired_at, Types::Timestamp
    end

    class Guidance < Value
      attribute :message_id, Types::Identifier
      attribute :conversation_id, Types::Identifier
      attribute :source, Types::GuidanceSource
      attribute :policy_status, Types::EvidencePolicyStatus
      attribute :recorded_at, Types::Timestamp
    end

    class InterpretationProposal < Value
      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :assessment, Interpretations::InterpretationAssessmentV1
      attribute :proposed_at, Types::Timestamp
    end

    class InterpretationAdjudication < Value
      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :action, Types::InterpretationAdjudicationAction
      attribute :outcome, Types::InterpretationAdjudicationOutcome
      attribute :policy_status, Types::InterpretationPolicyStatus
      attribute :slot, Interpretations::InterpretationSlotV1.optional
      attribute :adjudicated_at, Types::Timestamp
    end

    class DecisionActivation < Value
      PartitionReceipt = Decisions::DecisionPartitionReceiptV1

      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :outcome, Types::DecisionActivationOutcome
      attribute :policy_status, Types::DecisionPolicyStatus
      attribute :definition_digest, Types::Sha256Digest
      attribute :slot, Decisions::DecisionSlotV1.optional
      attribute :partitions, Types::Array.of(PartitionReceipt).constrained(min_size: 1, max_size: 32)
      attribute :activated_at, Types::Timestamp
    end

    Type = ChangeSet |
           WorkItem |
           Dependency |
           Attempt |
           LeaseSet |
           LeaseSetExpansion |
           LeaseSetRenewal |
           LeaseSetRelease |
           ResourceLeaseExpiry |
           Guidance |
           InterpretationProposal |
           InterpretationAdjudication |
           DecisionActivation
  end
end
