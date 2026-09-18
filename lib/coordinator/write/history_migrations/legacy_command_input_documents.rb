# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    module LegacyCommandInputDocuments
      LegacySkillId = Types::String.constrained(format: /\Askill:v1:[0-9a-f]{64}\z/)

      class PublishSkillRevisionInputV2 < Value
        Asset = CommandInputDocuments::SkillAssetV2

        attribute :actor, CommandInputDocuments::ActorV1
        attribute :name, Types::SkillName
        attribute :scope, Types::SkillScope
        attribute :skill_id, LegacySkillId
        attribute :expected_revision, Types::SkillExpectedRevision
        attribute :description, Types::SkillDescription
        attribute :instructions, Types::SkillInstructions
        attribute :assets,
                  Types::Array.of(Asset).constrained(max_size: Types::SKILL_ASSET_MAXIMUM_COUNT)
        attribute :content_digest, Types::Sha256Digest
      end

      class PublishSkillRevisionV2 < CommandInputDocuments::PublishSkillRevisionBase
        attribute :input, PublishSkillRevisionInputV2
      end

      class DevelopmentArtifactV2 < Value
        Content = Coordinator::Write::Content::TextV1 | Coordinator::Write::Content::BinaryV1

        attribute :artifact_id, LegacyDevelopmentArtifactTypes::ArtifactId
        attribute :observation_id, LegacyDevelopmentArtifactTypes::ObservationId
        attribute :scope, Types::DevelopmentArtifactScope
        attribute :title, Types::DevelopmentArtifactTitle
        attribute :kind, Types::DevelopmentArtifactKind
        attribute :labels, Types::DevelopmentArtifactLabels
        attribute :content, Content
        attribute :source, CommandInputDocuments::DevelopmentArtifactSourceV1
      end

      class CaptureDevelopmentArtifactInputV2 < Value
        attribute :actor, CommandInputDocuments::ActorV1
        attribute :artifact, DevelopmentArtifactV2
      end

      class CaptureDevelopmentArtifactV2 < CommandInputDocuments::CaptureDevelopmentArtifactBase
        attribute :input, CaptureDevelopmentArtifactInputV2
      end

      class DevelopmentArtifactRelationV1 < Value
        attribute :relation_id, LegacyDevelopmentArtifactTypes::RelationId
        attribute :source_artifact_id, LegacyDevelopmentArtifactTypes::ArtifactId
        attribute :relation, Types::DevelopmentArtifactRelationKind
        attribute :target, CommandInputDocuments::DevelopmentArtifactRelationTargetV1
        attribute :attributes, CommandInputDocuments::DevelopmentArtifactRelationAttributesV1

        def relation_attributes
          self[:attributes]
        end
      end

      class DeclareDevelopmentArtifactRelationInputV1 < Value
        attribute :actor, CommandInputDocuments::ActorV1
        attribute :artifact_relation, DevelopmentArtifactRelationV1
        attribute? :supersedes_relation_id, LegacyDevelopmentArtifactTypes::RelationId.optional
        attribute? :supersession_reason,
                   Types::DevelopmentArtifactRelationSupersessionReason.optional
      end

      class DeclareDevelopmentArtifactRelationV1 < CommandInputDocuments::BaseV1
        attribute :tool_name, Types::String.enum("development_artifact_relation_declare")
        attribute :input, DeclareDevelopmentArtifactRelationInputV1
      end

      class RecordGuidanceV1 < CommandInputDocuments::BaseV1
        attribute :tool_name, Types::String.enum("guidance_record")
        attribute :input, CommandInputDocuments::RecordGuidanceInputV1
      end

      class OperationBatchItemV1 < Value
        attribute :index, Types::OperationBatchItemIndex
        attribute :command_input, Types::Hash
        attribute :canonical_input_digest, Types::Sha256Digest
      end

      class CreateOperationBatchInputV1 < Value
        Item = OperationBatchItemV1

        attribute :actor, CommandInputDocuments::ActorV1
        attribute :batch_id, Types::OperationBatchId
        attribute :target_tool, Types::OperationBatchTargetTool
        attribute :items, Types::Array.of(Item).constrained(
          min_size: 1,
          max_size: Types::OPERATION_BATCH_MAXIMUM_ITEMS
        )
        attribute :manifest_digest, Types::Sha256Digest
        attribute :encoded_byte_size, Types::OperationBatchEncodedByteSize
        attribute :page_size, Types::OperationBatchPageSize
      end

      class CreateOperationBatchV1 < CommandInputDocuments::BaseV1
        attribute :tool_name, Types::String.enum(
          "skill_publish_batch",
          "development_artifact_capture_batch",
          "development_artifact_relation_declare_batch"
        )
        attribute :input, CreateOperationBatchInputV1
      end

      DEFINITIONS = {
        "repository_register" => CommandInputDocuments::RegisterRepositoryV1,
        "resource_resolve" => CommandInputDocuments::ResolveResourceV1,
        "change_set_create" => CommandInputDocuments::CreateChangeSetV1,
        "work_item_create" => CommandInputDocuments::CreateWorkItemV1,
        "work_item_dependency_declare" => CommandInputDocuments::DeclareWorkItemDependencyV1,
        "change_set_activate" => CommandInputDocuments::ActivateChangeSetV1,
        "work_item_acquire" => CommandInputDocuments::AcquireWorkItemV1,
        "work_item_complete" => CommandInputDocuments::CompleteWorkItemV1,
        "attempt_abandon" => CommandInputDocuments::AbandonAttemptV1,
        "guidance_record" => RecordGuidanceV1,
        "decision_interpretation_propose" => CommandInputDocuments::ProposeDecisionInterpretationV1,
        "write_set_reserve" => PostRemodelCommandInputDocuments::LegacyReserveWriteSetV1,
        "write_set_expand" => PostRemodelCommandInputDocuments::LegacyExpandWriteSetV1,
        "lease_renew" => PostRemodelCommandInputDocuments::LegacyRenewLeaseSetV1,
        "lease_release" => PostRemodelCommandInputDocuments::LegacyReleaseLeaseSetV1,
        "candidate_submit" => PostRemodelCommandInputDocuments::LegacySubmitCandidateV1,
        "skill_publish" => [ PublishSkillRevisionV2, CommandInputDocuments::PublishSkillRevisionV2 ],
        "development_artifact_capture" => [
          CaptureDevelopmentArtifactV2,
          CommandInputDocuments::CaptureDevelopmentArtifactV2
        ],
        "development_artifact_relation_declare" => [
          DeclareDevelopmentArtifactRelationV1,
          CommandInputDocuments::DeclareDevelopmentArtifactRelationV1
        ],
        "skill_publish_batch" => [ CreateOperationBatchV1, CommandInputDocuments::CreateOperationBatchV1 ],
        "development_artifact_capture_batch" => [
          CreateOperationBatchV1,
          CommandInputDocuments::CreateOperationBatchV1
        ],
        "development_artifact_relation_declare_batch" => [
          CreateOperationBatchV1,
          CommandInputDocuments::CreateOperationBatchV1
        ]
      }.freeze
    end
  end
end
