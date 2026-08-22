# frozen_string_literal: true

module Coordinator::Write
  module CommandInputDocuments
    class ActorV1 < Value
      attribute :actor_kind, Types::ActorKind
      attribute :actor_id, Types::Identifier
    end

    class BaseV1 < Value
      attribute :schema, Types::String.enum("command-input/v1")
      attribute :command_id, Types::Identifier
    end

    class CreateChangeSetInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :goal, Types::Goal
      attribute :acceptance_criteria, Types::AcceptanceCriteria
    end

    class CreateChangeSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("change_set_create")
      attribute :input, CreateChangeSetInputV1
    end

    class CreateWorkItemInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :goal, Types::Goal
      attribute :acceptance_criteria, Types::WorkItemAcceptanceCriteria
    end

    class CreateWorkItemV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_item_create")
      attribute :input, CreateWorkItemInputV1
    end

    class DeclareWorkItemDependencyInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :dependency_id, Types::Identifier
      attribute :producer_work_item_id, Types::Identifier
      attribute :consumer_work_item_id, Types::Identifier
      attribute :dependency_kind, Types::DependencyKind
      attribute :required_output, RequiredOutput.optional
    end

    class DeclareWorkItemDependencyV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_item_dependency_declare")
      attribute :input, DeclareWorkItemDependencyInputV1
    end

    class ActivateChangeSetInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
    end

    class ActivateChangeSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("change_set_activate")
      attribute :input, ActivateChangeSetInputV1
    end

    class RepositorySnapshotV1 < Value
      attribute :repository_id, Types::RepositoryId
      attribute :object_format, Types::GitObjectFormat
      attribute :commit_oid, Types::GitOid
    end

    class AcquireWorkItemInputV1 < Value
      Snapshot = RepositorySnapshotV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :base_snapshots, Types::Array.of(Snapshot).constrained(max_size: 100)
    end

    class AcquireWorkItemV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_item_acquire")
      attribute :input, AcquireWorkItemInputV1
    end

    class FileResourceV1 < Value
      attribute :kind, Types::ResourceKind
      attribute :path, Types::ResourcePath
      attribute :base_blob_oid, Types::GitOid.optional
      attribute :resource_key, Types::String
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
    end

    class ReserveWriteSetInputV1 < Value
      Resource = FileResourceV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :base_commit_oid, Types::GitOid
      attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
      attribute :lease_duration_seconds, Types::LeaseDurationSeconds
    end

    class ReserveWriteSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("write_set_reserve")
      attribute :input, ReserveWriteSetInputV1
    end

    class ExpandWriteSetInputV1 < Value
      Resource = FileResourceV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :lease_set_id, Types::UuidV7
      attribute :repository_id, Types::RepositoryId
      attribute :base_commit_oid, Types::GitOid
      attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
    end

    class ExpandWriteSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("write_set_expand")
      attribute :input, ExpandWriteSetInputV1
    end

    class LeaseRenewalReferenceV1 < Value
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :lease_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
    end

    class RenewLeaseSetInputV1 < Value
      Reference = LeaseRenewalReferenceV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :lease_set_id, Types::UuidV7
      attribute :leases, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
      attribute :lease_duration_seconds, Types::LeaseDurationSeconds
    end

    class RenewLeaseSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("lease_renew")
      attribute :input, RenewLeaseSetInputV1
    end

    class LeaseReleaseReferenceV1 < Value
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :lease_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
    end

    class ReleaseLeaseSetInputV1 < Value
      Reference = LeaseReleaseReferenceV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :lease_set_id, Types::UuidV7
      attribute :leases, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
    end

    class ReleaseLeaseSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("lease_release")
      attribute :input, ReleaseLeaseSetInputV1
    end

    class GuidanceAnchorsV1 < Value
      attribute :repository_ids, Types::GuidanceRepositoryIds
      attribute :change_set_id, Types::Identifier.optional
      attribute :work_item_id, Types::Identifier.optional
      attribute :attempt_id, Types::Identifier.optional
    end

    class RecordGuidanceInputV1 < Value
      attribute :actor, ActorV1
      attribute :message_id, Types::Identifier
      attribute :conversation_id, Types::Identifier
      attribute :source, Types::GuidanceSource
      attribute :text, Types::GuidanceText
      attribute :anchors, GuidanceAnchorsV1
    end

    class RecordGuidanceV1 < BaseV1
      attribute :tool_name, Types::String.enum("guidance_record")
      attribute :input, RecordGuidanceInputV1
    end

    class ProposeDecisionInterpretationInputV1 < Value
      Ambiguity = Interpretations::InterpretationAmbiguityV1

      attribute :actor, ActorV1
      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :source_span, Interpretations::SourceSpanV1.optional
      attribute :classifier, Interpretations::ClassifierAttributionV1
      attribute :proposed_decision, Interpretations::SubmittedDecisionV1
      attribute :ambiguities, Types::Array.of(Ambiguity).constrained(max_size: 20)
    end

    class ProposeDecisionInterpretationV1 < BaseV1
      attribute :tool_name, Types::String.enum("decision_interpretation_propose")
      attribute :input, ProposeDecisionInterpretationInputV1
    end

    class AdjudicateDecisionInterpretationInputV1 < Value
      attribute :actor, ActorV1
      attribute :source_message_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :action, Types::InterpretationAdjudicationAction
      attribute :rationale, Interpretations::AdjudicationRationaleV1
      attribute :clarification, Interpretations::AdjudicationClarificationV1.optional
    end

    class AdjudicateDecisionInterpretationV1 < BaseV1
      attribute :tool_name, Types::String.enum("decision_interpretation_adjudicate")
      attribute :input, AdjudicateDecisionInterpretationInputV1
    end

    class ActivateDecisionInputV1 < Value
      attribute :actor, ActorV1
      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :rationale, Decisions::DecisionActivationRationaleV1
    end

    class ActivateDecisionV1 < BaseV1
      attribute :tool_name, Types::String.enum("decision_activate")
      attribute :input, ActivateDecisionInputV1
    end

    class ExpireResourceLeaseInputV1 < Value
      attribute :actor, ActorV1
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :lease_id, Types::UuidV7
      attribute :lease_set_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
      attribute :expected_expires_at, Types::Timestamp
    end

    class ExpireResourceLeaseV1 < BaseV1
      attribute :tool_name, Types::String.enum("lease_expire_policy")
      attribute :input, ExpireResourceLeaseInputV1
    end

    Type = CreateChangeSetV1 |
           CreateWorkItemV1 |
           DeclareWorkItemDependencyV1 |
           ActivateChangeSetV1 |
           AcquireWorkItemV1 |
           ReserveWriteSetV1 |
           ExpandWriteSetV1 |
           RenewLeaseSetV1 |
           ReleaseLeaseSetV1 |
           RecordGuidanceV1 |
           ProposeDecisionInterpretationV1 |
           AdjudicateDecisionInterpretationV1 |
           ActivateDecisionV1

    DigestType = Type | ExpireResourceLeaseV1
  end
end
