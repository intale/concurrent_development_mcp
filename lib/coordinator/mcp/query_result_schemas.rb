# frozen_string_literal: true

module Coordinator
  module Mcp
    module QueryResultSchemas
      DATA_CLASSES = {
        "coord_context" => [ Coordinator::Read::QueryResultV1::ContextData,
                             Coordinator::Read::QueryResultV1::NotModifiedData ],
        "coordination_list" => [ Coordinator::Read::QueryResultV1::CoordinationPageData ],
        "attempt_list" => [ Coordinator::Read::QueryResultV1::AttemptHistoryPageData ],
        "operation_get" => [ Coordinator::Read::QueryResultV1::OperationData ],
        "guidance_get" => [ Coordinator::Read::QueryResultV1::GuidanceData ],
        "decision_interpretation_list" => [ Coordinator::Read::QueryResultV1::InterpretationPageData ],
        "decision_get" => [ Coordinator::Read::QueryResultV1::DecisionData ],
        "decision_list" => [ Coordinator::Read::QueryResultV1::DecisionPageData ],
        "decision_resolve" => [ Coordinator::Read::QueryResultV1::DecisionContextData ],
        "agent_choice_get" => [ Coordinator::Read::QueryResultV1::AgentChoiceData ],
        "agent_choice_impact_list" => [ Coordinator::Read::QueryResultV1::AgentChoiceImpactPageData ],
        "candidate_get" => [ Coordinator::Read::QueryResultV1::CandidateData ],
        "candidate_list" => [ Coordinator::Read::QueryResultV1::CandidatePageData ],
        "candidate_impact_get" => [ Coordinator::Read::QueryResultV1::CandidateImpactData ],
        "repository_list" => [ Coordinator::Read::QueryResultV1::RepositoryPageData ],
        "resource_get" => [ Coordinator::Read::QueryResultV1::ResourceData ],
        "resource_list" => [ Coordinator::Read::QueryResultV1::ResourcePageData ],
        "skill_get" => [ Coordinator::Read::QueryResultV1::SkillData ],
        "skill_list" => [ Coordinator::Read::QueryResultV1::SkillPageData ],
        "development_search" => [ Coordinator::Read::QueryResultV1::SearchPageData ],
        "skill_asset_get" => [ Coordinator::Read::QueryResultV1::SkillAssetData ],
        "development_artifact_get" => [ Coordinator::Read::QueryResultV1::DevelopmentArtifactData ],
        "development_artifact_content_get" => [ Coordinator::Read::QueryResultV1::DevelopmentArtifactContentData ],
        "development_artifact_list" => [ Coordinator::Read::QueryResultV1::DevelopmentArtifactPageData ],
        "development_artifact_relation_list" => [ Coordinator::Read::QueryResultV1::DevelopmentArtifactRelationPageData ],
        "development_artifact_locator_resolve" => [ Coordinator::Read::QueryResultV1::DevelopmentArtifactLocatorPageData ],
        "operation_batch_get" => [ Coordinator::Read::QueryResultV1::OperationBatchData ],
        "verification_obligations_list" => [ Coordinator::Read::QueryResultV1::VerificationObligationPageData ],
        "merge_snapshot_get" => [ Coordinator::Read::QueryResultV1::MergeSnapshotData ],
        "release_set_get" => [ Coordinator::Read::QueryResultV1::ReleaseSetData ]
      }.freeze

      module_function

      def for(tool_name)
        data_classes = DATA_CLASSES.fetch(tool_name)
        compiler = DryStructSchema.new
        data_schemas = data_classes.map { compiler.call(_1) }
        data_schemas << compiler.call(Coordinator::Read::QueryResultV1::EmptyData)
        data_schemas << compiler.call(Coordinator::Read::QueryResultV1::DomainError)

        Schemas.envelope(
          data: { oneOf: data_schemas },
          next_action: NextActionSchemas.schema
        )
      end
    end
  end
end
