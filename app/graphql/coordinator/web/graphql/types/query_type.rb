# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class QueryType < BaseObject
    graphql_name "Query"
    description "Read-only access to the latest available coordination projections."

    field :projects, ProjectConnectionType, null: false, connection: false do
      description "Discover exact Project scopes with bounded Repository-member previews."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :repositories_first, Integer, required: false, default_value: 3
      argument :search, String, required: false
      argument :sort, ProjectSortEnum, required: false, default_value: "scope_asc"
    end

    field :project, ProjectOverviewType, null: true do
      description "Resolve one server-issued Project reference to its exact scope and Repository members."
      argument :project_ref, ID, required: true
      argument :repositories_after, String, required: false
      argument :repositories_first, Integer, required: false, default_value: 20
    end

    field :project_change_sets, CoordinationChangeSetConnectionType, null: true, connection: false do
      description "Page current ChangeSets whose WorkItems belong to the exact Project scope."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :project_ref, ID, required: true
    end

    field :project_change_set, CoordinationChangeSetType, null: true do
      description "Resolve one ChangeSet only when it belongs to the exact Project scope."
      argument :change_set_id, ID, required: true
      argument :project_ref, ID, required: true
    end

    field :project_work_items, CoordinationWorkItemConnectionType, null: true, connection: false do
      description "Page current WorkItems in the exact Project scope with server-driven filters."
      argument :after, String, required: false
      argument :agent_id, String, required: false
      argument :change_set_id, ID, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :presentation_statuses, [ CoordinationPresentationStatusEnum ], required: false
      argument :project_ref, ID, required: true
      argument :sort, WorkItemSortEnum, required: false, default_value: "work_item_id_asc"
    end

    field :project_work_item, ProjectCoordinationType, null: true do
      description "Resolve one project WorkItem with its current or latest Attempt and checkpoint."
      argument :project_ref, ID, required: true
      argument :work_item_id, ID, required: true
    end

    field :project_dependencies, CoordinationDependencyConnectionType, null: true, connection: false do
      description "Page current WorkItem dependencies touching the exact Project scope."
      argument :after, String, required: false
      argument :blocking, Boolean, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :project_ref, ID, required: true
    end

    field :project_dependency, CoordinationDependencyType, null: true do
      description "Resolve one dependency only when a producer or consumer belongs to the Project."
      argument :dependency_id, ID, required: true
      argument :project_ref, ID, required: true
    end

    field :project_resources, ProjectResourcesType, null: true do
      description "Latest available resource inventory and factual active leases for one project."
      argument :active_leases_after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :repository_id, ID, required: true
      argument :resource_kind, ResourceKindEnum, required: false
      argument :resource_lifecycle_status, ResourceLifecycleStatusEnum, required: false
      argument :resources_after, String, required: false
    end

    field :project_knowledge, ProjectKnowledgeType, null: true do
      description "Current Skills and Development Artifacts for one registered project."
      argument :artifacts_after, String, required: false
      argument :artifact_kind, DevelopmentArtifactKindEnum, required: false
      argument :artifact_labels, [ String ], required: false
      argument :artifact_source_kind, DevelopmentArtifactSourceKindEnum, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :repository_id, ID, required: true
      argument :skill_name, String, required: false
      argument :skills_after, String, required: false
    end

    field :project_skill, ProjectSkillType, null: true do
      description "Current projected revision of one Skill in a project's exact scope."
      argument :name, String, required: true
      argument :repository_id, ID, required: true
    end

    field :project_skill_asset, ProjectSkillAssetType, null: true do
      description "Current projected content of one Skill asset in a project's exact scope."
      argument :name, String, required: true
      argument :path, String, required: true
      argument :repository_id, ID, required: true
    end

    field :project_artifact, ProjectArtifactType, null: true do
      description "One project-scoped Artifact with passive content and active relationships."
      argument :artifact_id, ID, required: true
      argument :direction,
               ArtifactRelationDirectionEnum,
               required: false,
               default_value: "both"
      argument :first, Integer, required: false, default_value: 20
      argument :relation, DevelopmentArtifactRelationKindEnum, required: false
      argument :relations_after, String, required: false
      argument :repository_id, ID, required: true
    end

    field :project_governance, GovernanceTypes::ProjectGovernanceType, null: true do
      description "Project-scoped Decisions, guidance, AgentChoices, and decision impacts."
      argument :after_choice, String, required: false
      argument :after_decision, String, required: false
      argument :after_guidance, String, required: false
      argument :after_impact, String, required: false
      argument :choice_status, GovernanceTypes::AgentChoiceStatusEnum, required: false
      argument :choice_type, GovernanceTypes::AgentChoiceTypeEnum, required: false
      argument :decision_policy_status, GovernanceTypes::DecisionPolicyStatusEnum, required: false
      argument :decision_topic_id, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :guidance_source, GovernanceTypes::GuidanceSourceEnum, required: false
      argument :impact_outcome, GovernanceTypes::AgentChoiceImpactOutcomeEnum, required: false
      argument :repository_id, ID, required: true
    end

    field :project_decision, GovernanceTypes::ProjectDecisionType, null: true do
      description "One Decision deterministically associated with the exact project."
      argument :decision_id, ID, required: true
      argument :repository_id, ID, required: true
    end

    field :project_guidance, GovernanceTypes::ProjectGuidanceType, null: true do
      description "One project-scoped guidance fact and its bounded interpretation proposals."
      argument :interpretations_after, String, required: false
      argument :interpretations_first, Integer, required: false, default_value: 20
      argument :message_id, ID, required: true
      argument :repository_id, ID, required: true
    end

    field :project_agent_choice, GovernanceTypes::ProjectAgentChoiceType, null: true do
      description "One project AgentChoice and its bounded decision-impact assessments."
      argument :choice_id, ID, required: true
      argument :impacts_after, String, required: false
      argument :impacts_first, Integer, required: false, default_value: 20
      argument :repository_id, ID, required: true
    end

    field :command_receipts, GovernanceTypes::CommandReceiptConnectionType, null: false, connection: false do
      description "Global command-completion audit facts without inferred project attribution."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :status, GovernanceTypes::CommandReceiptStatusEnum, required: false
      argument :tool_name, String, required: false
    end

    field :command_receipt, GovernanceTypes::CommandReceiptType, null: true do
      description "One command-completion audit fact."
      argument :command_id, ID, required: true
    end

    field :project_delivery, DeliveryTypes::ProjectDeliveryType, null: true do
      description "Latest project-related Candidate, verification, merge, and ReleaseSet projections."
      argument :after_candidate, String, required: false
      argument :after_merge_snapshot, String, required: false
      argument :after_obligation, String, required: false
      argument :after_release_set, String, required: false
      argument :candidate_change_set_id, ID, required: false
      argument :candidate_checkpoint_kind, DeliveryTypes::CandidateCheckpointKindEnum, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :obligation_change_set_id, ID, required: false
      argument :obligation_status, DeliveryTypes::VerificationObligationStatusEnum, required: false
      argument :release_change_set_id, ID, required: false
      argument :release_status, DeliveryTypes::ReleaseSetStatusEnum, required: false
      argument :repository_id, ID, required: true
      argument :sort, DeliveryTypes::DeliverySortEnum, required: false, default_value: "newest_first"
    end

    field :project_candidate_checkpoint, DeliveryTypes::ProjectCandidateCheckpointType, null: true do
      description "One project Candidate checkpoint and one bounded semantic impact direction."
      argument :candidate_id, ID, required: true
      argument :direction, DeliveryTypes::CandidateImpactDirectionEnum, required: false, default_value: "outgoing"
      argument :first, Integer, required: false, default_value: 20
      argument :impacts_after, String, required: false
      argument :repository_id, ID, required: true
    end

    field :project_verification_obligation,
          DeliveryTypes::ProjectVerificationObligationType,
          null: true do
      description "One project-related verification obligation with bounded evidence facts."
      argument :evidence_after, String, required: false
      argument :evidence_first, Integer, required: false, default_value: 20
      argument :obligation_id, ID, required: true
      argument :repository_id, ID, required: true
    end

    field :project_merge_snapshot, DeliveryTypes::ProjectMergeSnapshotType, null: true do
      description "One project merge snapshot with candidates and bounded authorization decisions."
      argument :authorizations_after, String, required: false
      argument :authorizations_first, Integer, required: false, default_value: 20
      argument :merge_snapshot_id, ID, required: true
      argument :repository_id, ID, required: true
    end

    field :project_release_set, DeliveryTypes::ProjectReleaseSetType, null: true do
      description "One ReleaseSet whose persisted ordered members include the exact project."
      argument :release_set_id, ID, required: true
      argument :repository_id, ID, required: true
    end

    field :operation_batches,
          DeliveryTypes::OperationBatchConnectionType,
          null: false,
          connection: false do
      description "Global operation-batch progress without inferred project attribution."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :sort, DeliveryTypes::DeliverySortEnum, required: false, default_value: "newest_first"
      argument :status, DeliveryTypes::OperationBatchStatusEnum, required: false
      argument :target_tool, DeliveryTypes::OperationBatchToolEnum, required: false
    end

    field :operation_batch, DeliveryTypes::OperationBatchDetailType, null: true do
      description "One global operation batch with bounded typed item outcomes."
      argument :batch_id, ID, required: true
      argument :first, Integer, required: false, default_value: 50
      argument :items_after, String, required: false
    end

    def projects(first:, repositories_first:, sort:, after: nil, search: nil)
      after_scope = Coordinator::Web::Graphql::ProjectCursor.decode_projects(
        after,
        search:,
        sort:
      )
      page = project_catalog.page(
        search:,
        sort:,
        after_scope:,
        first:,
        repositories_first:
      )
      {
        nodes: page.items.map { project_payload(_1) },
        page_info: {
          end_cursor: page.next_scope && Coordinator::Web::Graphql::ProjectCursor.encode_projects(
            after_scope: page.next_scope,
            search:,
            sort:
          ),
          has_next_page: page.has_more
        }
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectCatalogQueryError => error
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "INVALID_INPUT", details: error.details }
      )
    end

    def project(project_ref:, repositories_first:, repositories_after: nil)
      after_repository_id = Coordinator::Web::Graphql::ProjectCursor.decode_repositories(
        repositories_after,
        project_ref:
      )
      overview = project_catalog.overview(
        project_ref:,
        after_repository_id:,
        repositories_first:
      )
      project_payload(overview) if overview
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "INVALID_PROJECT_REFERENCE" }
      )
    rescue Coordinator::Read::Web::ProjectCatalogQueryError => error
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "INVALID_INPUT", details: error.details }
      )
    end

    def project_change_sets(project_ref:, first:, after: nil)
      filters = coordination_filters(project_ref:, first:)
      cursor = coordination_cursor(after, "change-sets", filters:)
      page = coordination_dashboard.page(
        project_ref:,
        kind: "change_sets",
        first:,
        after_id: cursor&.fetch("id", nil)
      )
      coordination_connection(page, "change-sets", filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::CoordinationDashboardQueryError => error
      raise_coordination_query_error(error)
    end

    def project_change_set(project_ref:, change_set_id:)
      coordination_dashboard.detail(project_ref:, kind: "change_sets", id: change_set_id)
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::CoordinationDashboardQueryError => error
      raise_coordination_query_error(error)
    end

    def project_work_items(
      project_ref:,
      first:,
      sort:,
      after: nil,
      agent_id: nil,
      change_set_id: nil,
      presentation_statuses: nil
    )
      statuses = Array(presentation_statuses).uniq.sort
      filters = coordination_filters(
        project_ref:,
        first:,
        sort:,
        presentation_statuses: statuses,
        change_set_id:,
        agent_id:
      )
      cursor = coordination_cursor(after, "work-items", filters:)
      page = coordination_dashboard.page(
        project_ref:,
        kind: "work_items",
        first:,
        after_id: cursor&.fetch("id", nil),
        after_sort_value: cursor&.fetch("sort_value", nil),
        presentation_statuses: statuses,
        work_item_sort: sort,
        change_set_id:,
        agent_id:
      )
      coordination_connection(page, "work-items", filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::CoordinationDashboardQueryError => error
      raise_coordination_query_error(error)
    end

    def project_work_item(project_ref:, work_item_id:)
      coordination_dashboard.detail(project_ref:, kind: "work_items", id: work_item_id)
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::CoordinationDashboardQueryError => error
      raise_coordination_query_error(error)
    end

    def project_dependencies(project_ref:, first:, after: nil, blocking: nil)
      filters = coordination_filters(project_ref:, first:, blocking:)
      cursor = coordination_cursor(after, "dependencies", filters:)
      page = coordination_dashboard.page(
        project_ref:,
        kind: "dependencies",
        first:,
        after_id: cursor&.fetch("id", nil),
        blocking:
      )
      coordination_connection(page, "dependencies", filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::CoordinationDashboardQueryError => error
      raise_coordination_query_error(error)
    end

    def project_dependency(project_ref:, dependency_id:)
      coordination_dashboard.detail(project_ref:, kind: "dependencies", id: dependency_id)
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::CoordinationDashboardQueryError => error
      raise_coordination_query_error(error)
    end

    def project_resources(
      repository_id:,
      first:,
      active_leases_after: nil,
      resource_kind: nil,
      resource_lifecycle_status: nil,
      resources_after: nil
    )
      resource_after_id = Coordinator::Web::Graphql::ResourceBrowserCursor.decode_resources(
        resources_after,
        repository_id:,
        resource_kind:,
        lifecycle_status: resource_lifecycle_status
      )
      lease_cursor = Coordinator::Web::Graphql::ResourceBrowserCursor.decode_active_leases(
        active_leases_after,
        repository_id:
      )
      browser = Coordinator::Read::Web::Queries::ProjectResources.new.call(
        repository_id:,
        first:,
        resource_after_id:,
        lease_after_id: lease_cursor&.fetch(:after_id, nil),
        lease_as_of: lease_cursor&.fetch(:as_of, nil),
        resource_kind:,
        resource_lifecycle_status:
      )
      return unless browser

      {
        project: browser.project,
        resources: resource_connection(
          browser.resources,
          repository_id:,
          resource_kind:,
          lifecycle_status: resource_lifecycle_status
        ),
        active_leases: active_lease_connection(browser.active_leases, repository_id:, as_of: browser.lease_as_of)
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectResourcesQueryError => error
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "INVALID_INPUT", details: error.details }
      )
    end

    def project_knowledge(
      repository_id:,
      first:,
      artifact_kind: nil,
      artifact_labels: nil,
      artifact_source_kind: nil,
      artifacts_after: nil,
      skill_name: nil,
      skills_after: nil
    )
      labels = artifact_labels || []
      catalog = knowledge_browser.catalog(
        repository_id:,
        first:,
        skill_name:,
        after_skill_id: Coordinator::Web::Graphql::KnowledgeBrowserCursor.decode_skills(
          skills_after,
          repository_id:,
          skill_name:
        ),
        artifact_kind:,
        artifact_labels: labels,
        artifact_source_kind:,
        after_artifact_global_position: Coordinator::Web::Graphql::KnowledgeBrowserCursor.decode_artifacts(
          artifacts_after,
          repository_id:,
          artifact_kind:,
          labels:,
          source_kind: artifact_source_kind
        )
      )
      return unless catalog

      {
        project: catalog.project,
        skills: skill_connection(catalog.skills, repository_id:, skill_name:),
        artifacts: artifact_connection(
          catalog.artifacts,
          repository_id:,
          artifact_kind:,
          labels:,
          source_kind: artifact_source_kind
        )
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end

    def project_skill(repository_id:, name:)
      knowledge_browser.skill(repository_id:, name:)
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end

    def project_skill_asset(repository_id:, name:, path:)
      knowledge_browser.skill_asset(repository_id:, name:, path:)
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end

    def project_artifact(
      repository_id:,
      artifact_id:,
      first:,
      direction:,
      relation: nil,
      relations_after: nil
    )
      cursor = Coordinator::Web::Graphql::KnowledgeBrowserCursor.decode_relations(
        relations_after,
        repository_id:,
        artifact_id:,
        direction:,
        relation:
      )
      detail = knowledge_browser.artifact(
        repository_id:,
        artifact_id:,
        first:,
        direction:,
        relation:,
        cursor:
      )
      return unless detail

      {
        project: detail.project,
        artifact: detail.artifact,
        content: detail.content,
        relationships: artifact_relation_connection(
          detail.relationships,
          repository_id:,
          artifact_id:,
          direction:,
          relation:
        )
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end

    def project_governance(
      repository_id:,
      first:,
      after_choice: nil,
      after_decision: nil,
      after_guidance: nil,
      after_impact: nil,
      choice_status: nil,
      choice_type: nil,
      decision_policy_status: nil,
      decision_topic_id: nil,
      guidance_source: nil,
      impact_outcome: nil
    )
      decision_filters = governance_filters(
        repository_id:,
        topic_id: decision_topic_id,
        policy_status: decision_policy_status
      )
      guidance_filters = governance_filters(repository_id:, source: guidance_source)
      choice_filters = governance_filters(repository_id:, choice_type:, choice_status:)
      impact_filters = governance_filters(repository_id:, outcome: impact_outcome)
      impact_cursor = Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(
        after_impact,
        "impacts",
        filters: impact_filters
      )
      catalog = governance_browser.catalog(
        repository_id:,
        first:,
        decision_topic_id:,
        decision_policy_status:,
        after_decision_id: Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(
          after_decision,
          "decisions",
          filters: decision_filters
        ),
        guidance_source:,
        after_guidance_message_id: Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(
          after_guidance,
          "guidance",
          filters: guidance_filters
        ),
        choice_type:,
        choice_status:,
        after_choice_id: Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(
          after_choice,
          "choices",
          filters: choice_filters
        ),
        impact_outcome:,
        after_impact_global_position: impact_cursor&.fetch("global_position", nil),
        after_impact_assessment_id: impact_cursor&.fetch("assessment_id", nil)
      )
      return unless catalog

      {
        project: catalog.project,
        decisions: governance_decision_connection(catalog.decisions, filters: decision_filters),
        guidance: governance_guidance_connection(catalog.guidance, filters: guidance_filters),
        choices: governance_choice_connection(catalog.choices, filters: choice_filters),
        impacts: governance_impact_connection(catalog.impacts, filters: impact_filters)
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    def project_decision(repository_id:, decision_id:)
      governance_browser.decision(repository_id:, decision_id:)
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    def project_guidance(
      repository_id:,
      message_id:,
      interpretations_first:,
      interpretations_after: nil
    )
      filters = governance_filters(repository_id:, message_id:)
      detail = governance_browser.guidance(
        repository_id:,
        message_id:,
        first: interpretations_first,
        after_revision: Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(
          interpretations_after,
          "interpretations",
          filters:
        ) || -1
      )
      return unless detail

      {
        project: detail.project,
        guidance: detail.guidance,
        interpretations: governance_interpretation_connection(detail.interpretations, filters:)
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    def project_agent_choice(repository_id:, choice_id:, impacts_first:, impacts_after: nil)
      filters = governance_filters(repository_id:, choice_id:)
      cursor = Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(
        impacts_after,
        "impacts",
        filters:
      )
      detail = governance_browser.choice(
        repository_id:,
        choice_id:,
        first: impacts_first,
        after_impact_global_position: cursor&.fetch("global_position", nil),
        after_impact_assessment_id: cursor&.fetch("assessment_id", nil)
      )
      return unless detail

      {
        project: detail.project,
        choice: detail.choice,
        impacts: governance_impact_connection(detail.impacts, filters:)
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    def command_receipts(first:, after: nil, status: nil, tool_name: nil)
      filters = governance_filters(status:, tool_name:)
      page = governance_browser.receipts(
        first:,
        status:,
        tool_name:,
        after_command_id: Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(
          after,
          "receipts",
          filters:
        )
      )
      governance_receipt_connection(page, filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    rescue Coordinator::Read::Web::GovernanceBrowserReadError => error
      raise_governance_read_error(error)
    end

    def command_receipt(command_id:)
      governance_browser.receipt(command_id:)&.receipt
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    rescue Coordinator::Read::Web::GovernanceBrowserReadError => error
      raise_governance_read_error(error)
    end

    def project_delivery(
      repository_id:,
      first:,
      sort:,
      after_candidate: nil,
      after_merge_snapshot: nil,
      after_obligation: nil,
      after_release_set: nil,
      candidate_change_set_id: nil,
      candidate_checkpoint_kind: nil,
      obligation_change_set_id: nil,
      obligation_status: nil,
      release_change_set_id: nil,
      release_status: nil
    )
      candidate_filters = delivery_filters(
        repository_id:,
        change_set_id: candidate_change_set_id,
        checkpoint_kind: candidate_checkpoint_kind,
        sort:
      )
      obligation_filters = delivery_filters(
        repository_id:,
        change_set_id: obligation_change_set_id,
        status: obligation_status,
        sort:
      )
      merge_filters = delivery_filters(repository_id:, sort:)
      release_filters = delivery_filters(
        repository_id:,
        change_set_id: release_change_set_id,
        status: release_status,
        sort:
      )
      candidate_cursor = delivery_cursor(after_candidate, "candidates", filters: candidate_filters)
      obligation_cursor = delivery_cursor(after_obligation, "obligations", filters: obligation_filters)
      merge_cursor = delivery_cursor(after_merge_snapshot, "merge-snapshots", filters: merge_filters)
      release_cursor = delivery_cursor(after_release_set, "release-sets", filters: release_filters)
      catalog = delivery_browser.catalog(
        repository_id:,
        first:,
        sort:,
        candidate_change_set_id:,
        candidate_checkpoint_kind:,
        candidate_after_position: candidate_cursor&.fetch("position", nil),
        candidate_after_id: candidate_cursor&.fetch("id", nil),
        obligation_change_set_id:,
        obligation_status:,
        obligation_after_position: obligation_cursor&.fetch("position", nil),
        obligation_after_id: obligation_cursor&.fetch("id", nil),
        merge_after_position: merge_cursor&.fetch("position", nil),
        merge_after_id: merge_cursor&.fetch("id", nil),
        release_change_set_id:,
        release_status:,
        release_after_position: release_cursor&.fetch("position", nil),
        release_after_id: release_cursor&.fetch("id", nil)
      )
      return unless catalog

      {
        project: catalog.project,
        candidates: delivery_timeline_connection(catalog.candidates, "candidates", filters: candidate_filters),
        obligations: delivery_timeline_connection(catalog.obligations, "obligations", filters: obligation_filters),
        merge_snapshots: delivery_timeline_connection(
          catalog.merge_snapshots,
          "merge-snapshots",
          filters: merge_filters
        ),
        release_sets: delivery_timeline_connection(catalog.release_sets, "release-sets", filters: release_filters)
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def project_candidate_checkpoint(repository_id:, candidate_id:, direction:, first:, impacts_after: nil)
      filters = delivery_filters(repository_id:, candidate_id:, direction:)
      detail = delivery_browser.candidate(
        repository_id:,
        candidate_id:,
        direction:,
        first:,
        after_impact_position: delivery_cursor(
          impacts_after,
          "candidate-impacts",
          filters:
        )
      )
      return unless detail

      {
        project: detail.project,
        checkpoint: detail.candidate,
        impact_direction: detail.impacts.direction,
        impact_surface_digest: detail.impacts.impact_surface&.surface_digest,
        impact_relationships: {
          nodes: detail.impacts.relationships,
          page_info: {
            end_cursor: detail.impacts.next_global_position &&
              Coordinator::Web::Graphql::DeliveryBrowserCursor.encode(
                "candidate-impacts",
                filters:,
                cursor: detail.impacts.next_global_position
              ),
            has_next_page: detail.impacts.has_more
          }
        }
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def project_verification_obligation(
      repository_id:,
      obligation_id:,
      evidence_first:,
      evidence_after: nil
    )
      filters = delivery_filters(repository_id:, obligation_id:)
      cursor = delivery_cursor(evidence_after, "evidence", filters:)
      detail = delivery_browser.verification(
        repository_id:,
        obligation_id:,
        first: evidence_first,
        after_evidence_position: cursor&.fetch("position", nil),
        after_evidence_id: cursor&.fetch("id", nil)
      )
      return unless detail

      {
        project: detail.project,
        obligation: detail.obligation,
        required_evidence: detail.required_evidence,
        reasons: detail.reasons,
        evidence: delivery_timeline_connection(detail.evidence, "evidence", filters:)
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def project_merge_snapshot(
      repository_id:,
      merge_snapshot_id:,
      authorizations_first:,
      authorizations_after: nil
    )
      filters = delivery_filters(repository_id:, merge_snapshot_id:)
      cursor = delivery_cursor(authorizations_after, "authorizations", filters:)
      detail = delivery_browser.merge(
        repository_id:,
        merge_snapshot_id:,
        first: authorizations_first,
        after_authorization_position: cursor&.fetch("position", nil),
        after_authorization_id: cursor&.fetch("id", nil)
      )
      return unless detail

      {
        project: detail.project,
        snapshot: detail.snapshot,
        candidates: detail.candidates,
        authorizations: delivery_timeline_connection(
          detail.authorizations,
          "authorizations",
          filters:
        )
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def project_release_set(repository_id:, release_set_id:)
      delivery_browser.release(repository_id:, release_set_id:)
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def operation_batches(first:, sort:, after: nil, status: nil, target_tool: nil)
      filters = delivery_filters(sort:, status:, target_tool:)
      cursor = delivery_cursor(after, "operation-batches", filters:)
      page = delivery_browser.batches(
        first:,
        sort:,
        status:,
        target_tool:,
        after_position: cursor&.fetch("position", nil),
        after_id: cursor&.fetch("id", nil)
      )
      delivery_timeline_connection(page, "operation-batches", filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def operation_batch(batch_id:, first:, items_after: nil)
      filters = delivery_filters(batch_id:)
      detail = delivery_browser.batch(
        batch_id:,
        first:,
        after_index: delivery_cursor(items_after, "operation-batch-items", filters:)
      )
      return unless detail

      {
        batch: detail.batch,
        items: {
          nodes: detail.items.items,
          page_info: {
            end_cursor: detail.items.next_index &&
              Coordinator::Web::Graphql::DeliveryBrowserCursor.encode(
                "operation-batch-items",
                filters:,
                cursor: detail.items.next_index
              ),
            has_next_page: detail.items.has_more
          }
        }
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    private

    def project_catalog
      @project_catalog ||= Coordinator::Read::Web::Queries::ProjectCatalog.new
    end

    def project_payload(project)
      {
        project_ref: project.project_ref,
        scope: project.scope,
        display_label: project.display_label,
        repository_count: project.repository_count,
        repositories: project_repository_connection(project.repositories, project_ref: project.project_ref)
      }
    end

    def project_repository_connection(page, project_ref:)
      {
        nodes: page.items,
        total_count: page.total_count,
        page_info: {
          end_cursor: page.next_repository_id && Coordinator::Web::Graphql::ProjectCursor.encode_repositories(
            project_ref:,
            after_repository_id: page.next_repository_id
          ),
          has_next_page: page.has_more
        }
      }
    end

    def delivery_filters(**values)
      values.compact.transform_keys(&:to_s)
    end

    def delivery_cursor(value, kind, filters:)
      Coordinator::Web::Graphql::DeliveryBrowserCursor.decode(value, kind, filters:)
    end

    def delivery_timeline_connection(page, kind, filters:)
      cursor = page.next_cursor
      {
        nodes: page.items,
        page_info: {
          end_cursor: cursor && Coordinator::Web::Graphql::DeliveryBrowserCursor.encode(
            kind,
            filters:,
            cursor: { "position" => cursor.position, "id" => cursor.id }
          ),
          has_next_page: page.has_more
        }
      }
    end

    def coordination_connection(page, kind, filters:)
      return unless page

      cursor = page.next_cursor
      {
        nodes: page.items,
        page_info: {
          end_cursor: cursor && Coordinator::Web::Graphql::DashboardCursor.encode(
            kind,
            filters:,
            cursor: { "id" => cursor.id, "sort_value" => cursor.sort_value }
          ),
          has_next_page: page.has_more
        }
      }
    end

    def coordination_filters(**values)
      values.compact.transform_keys(&:to_s)
    end

    def coordination_cursor(value, kind, filters:)
      Coordinator::Web::Graphql::DashboardCursor.decode(value, kind, filters:)
    end

    def coordination_dashboard
      @coordination_dashboard ||= Coordinator::Read::Web::Queries::CoordinationDashboard.new
    end

    def raise_coordination_query_error(error)
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "INVALID_INPUT", details: error.details }
      )
    end

    def raise_invalid_project_reference(error)
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "INVALID_PROJECT_REFERENCE" }
      )
    end

    def resource_connection(page, repository_id:, resource_kind:, lifecycle_status:)
      {
        nodes: page.items,
        page_info: {
          end_cursor: page.next_resource_id && Coordinator::Web::Graphql::ResourceBrowserCursor.encode_resources(
            repository_id:,
            after_id: page.next_resource_id,
            resource_kind:,
            lifecycle_status:
          ),
          has_next_page: page.has_more
        }
      }
    end

    def active_lease_connection(page, repository_id:, as_of:)
      {
        as_of:,
        nodes: page.items,
        page_info: {
          end_cursor: page.next_lease_id && Coordinator::Web::Graphql::ResourceBrowserCursor.encode_active_leases(
            repository_id:,
            after_id: page.next_lease_id,
            as_of:
          ),
          has_next_page: page.has_more
        }
      }
    end

    def skill_connection(page, repository_id:, skill_name:)
      {
        nodes: page.items,
        page_info: {
          end_cursor: page.next_skill_id && Coordinator::Web::Graphql::KnowledgeBrowserCursor.encode_skills(
            repository_id:,
            after_id: page.next_skill_id,
            skill_name:
          ),
          has_next_page: page.has_more
        }
      }
    end

    def artifact_connection(page, repository_id:, artifact_kind:, labels:, source_kind:)
      {
        nodes: page.items,
        page_info: {
          end_cursor: page.next_global_position &&
            Coordinator::Web::Graphql::KnowledgeBrowserCursor.encode_artifacts(
              repository_id:,
              after_position: page.next_global_position,
              artifact_kind:,
              labels:,
              source_kind:
            ),
          has_next_page: page.has_more
        }
      }
    end

    def artifact_relation_connection(page, repository_id:, artifact_id:, direction:, relation:)
      {
        nodes: page.items,
        page_info: {
          end_cursor: page.has_more && Coordinator::Web::Graphql::KnowledgeBrowserCursor.encode_relations(
            repository_id:,
            artifact_id:,
            direction:,
            relation:,
            cursor: page.continuation_cursor
          ),
          has_next_page: page.has_more
        }
      }
    end

    def governance_filters(**filters)
      filters.to_h { |key, value| [ key.to_s, value ] }
    end

    def governance_decision_connection(page, filters:)
      governance_connection(
        page.items,
        page.has_more,
        page.next_decision_id,
        "decisions",
        filters:
      )
    end

    def governance_guidance_connection(page, filters:)
      governance_connection(
        page.items,
        page.has_more,
        page.next_message_id,
        "guidance",
        filters:
      )
    end

    def governance_choice_connection(page, filters:)
      governance_connection(
        page.items,
        page.has_more,
        page.next_choice_id,
        "choices",
        filters:
      )
    end

    def governance_impact_connection(page, filters:)
      governance_connection(
        page.items,
        page.has_more,
        page.next_cursor && {
          "global_position" => page.next_cursor.global_position,
          "assessment_id" => page.next_cursor.assessment_id
        },
        "impacts",
        filters:
      )
    end

    def governance_interpretation_connection(page, filters:)
      governance_connection(
        page.interpretations,
        !page.next_after_revision.nil?,
        page.next_after_revision,
        "interpretations",
        filters:
      )
    end

    def governance_receipt_connection(page, filters:)
      governance_connection(
        page.items,
        page.has_more,
        page.next_command_id,
        "receipts",
        filters:
      )
    end

    def governance_connection(nodes, has_more, cursor, kind, filters:)
      {
        nodes:,
        page_info: {
          end_cursor: cursor && Coordinator::Web::Graphql::GovernanceBrowserCursor.encode(
            kind,
            filters:,
            cursor:
          ),
          has_next_page: has_more
        }
      }
    end

    def knowledge_browser
      @knowledge_browser ||= Coordinator::Read::Web::Queries::KnowledgeBrowser.new
    end

    def governance_browser
      @governance_browser ||= Coordinator::Read::Web::Queries::GovernanceBrowser.new
    end

    def delivery_browser
      @delivery_browser ||= Coordinator::Read::Web::Queries::DeliveryBrowser.new
    end

    def raise_knowledge_query_error(error)
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "INVALID_INPUT", details: error.details }
      )
    end

    def raise_governance_query_error(error)
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "INVALID_INPUT", details: error.details }
      )
    end

    def raise_governance_read_error(error)
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "READ_MODEL_INVALID", details: error.details, retryable: true }
      )
    end

    def raise_delivery_query_error(error)
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "INVALID_INPUT", details: error.details }
      )
    end

    def raise_query_error(result)
      raise GraphQL::ExecutionError.new(
        result.data.message,
        extensions: { code: result.data.code.upcase, details: result.data.details }
      )
    end
  end
end
