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
      argument :sort, ProjectSortEnum, required: false, default_value: "newest_first"
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
      argument :status, CoordinationChangeSetStatusEnum, required: false
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
      argument :sort, WorkItemSortEnum, required: false, default_value: "updated_at_desc"
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

    field :project_resources, ProjectResourceConnectionType, null: true, connection: false do
      description "Page the latest available Resource inventory for the exact Project scope."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :path, String, required: false
      argument :project_ref, ID, required: true
      argument :resource_kind, ResourceKindEnum, required: false
      argument :resource_lifecycle_status, ResourceLifecycleStatusEnum, required: false
    end

    field :project_resource, ProjectResourceType, null: true do
      description "Resolve one Resource only when its Repository belongs to the exact Project scope."
      argument :project_ref, ID, required: true
      argument :resource_id, ID, required: true
    end

    field :project_active_resource_leases, ResourceLeaseConnectionType, null: true, connection: false do
      description "Page factual active Resource leases for the exact Project scope."
      argument :after, String, required: false
      argument :agent_id, String, required: false
      argument :attempt_id, ID, required: false
      argument :change_set_id, ID, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :project_ref, ID, required: true
      argument :work_item_id, ID, required: false
    end

    field :project_resource_lease, ResourceLeaseType, null: true do
      description "Resolve one projected Resource lease, including released, terminal, or expired history."
      argument :lease_id, ID, required: true
      argument :project_ref, ID, required: true
    end

    field :project_skills, SkillConnectionType, null: true, connection: false do
      description "Page current Skills shared by the exact Project scope."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :name, String, required: false
      argument :project_ref, ID, required: true
    end

    field :project_skill, ProjectSkillType, null: true do
      description "Current projected revision of one Skill in the exact Project scope."
      argument :name, String, required: true
      argument :project_ref, ID, required: true
    end

    field :project_skill_asset, ProjectSkillAssetType, null: true do
      description "Current projected content of one Skill asset in the exact Project scope."
      argument :name, String, required: true
      argument :path, String, required: true
      argument :project_ref, ID, required: true
    end

    field :skills, SkillConnectionType, null: false, connection: false do
      description "Page all current Skills, optionally filtered by exact Project and exact name."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :name, String, required: false
      argument :project_scope, String, required: false
    end

    field :skill, ProjectSkillType, null: true do
      description "Resolve one current Skill by its stable identity."
      argument :skill_id, ID, required: true
    end

    field :skill_asset, ProjectSkillAssetType, null: true do
      description "Resolve one current Skill asset by Skill identity and exact path."
      argument :path, String, required: true
      argument :skill_id, ID, required: true
    end

    field :project_artifacts, DevelopmentArtifactConnectionType, null: true, connection: false do
      description "Page current Development Artifacts shared by the exact Project scope."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :kind, DevelopmentArtifactKindEnum, required: false
      argument :labels, [ String ], required: false
      argument :project_ref, ID, required: true
      argument :source_kind, DevelopmentArtifactSourceKindEnum, required: false
    end

    field :project_artifact, ProjectArtifactType, null: true do
      description "One Project-scoped Artifact with its passive projected content."
      argument :artifact_id, ID, required: true
      argument :project_ref, ID, required: true
    end

    field :project_artifact_relationships, ProjectArtifactRelationshipsType, null: true do
      description "Page active semantic relationships for one Project-scoped Artifact."
      argument :artifact_id, ID, required: true
      argument :direction,
               ArtifactRelationDirectionEnum,
               required: false,
               default_value: "both"
      argument :first, Integer, required: false, default_value: 20
      argument :relation, DevelopmentArtifactRelationKindEnum, required: false
      argument :after, String, required: false
      argument :project_ref, ID, required: true
    end

    field :project_decisions, GovernanceTypes::DecisionConnectionType, null: true, connection: false do
      description "Page Decisions associated with any Repository member of the exact Project scope."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :policy_status, GovernanceTypes::DecisionPolicyStatusEnum, required: false
      argument :project_ref, ID, required: true
      argument :topic_id, String, required: false
    end

    field :project_guidance_messages, GovernanceTypes::GuidanceConnectionType, null: true, connection: false do
      description "Page Guidance associated with any Repository member of the exact Project scope."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :project_ref, ID, required: true
      argument :source, GovernanceTypes::GuidanceSourceEnum, required: false
    end

    field :project_agent_choices, GovernanceTypes::AgentChoiceConnectionType, null: true, connection: false do
      description "Page AgentChoices associated with any Repository member of the exact Project scope."
      argument :after, String, required: false
      argument :choice_type, GovernanceTypes::AgentChoiceTypeEnum, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :project_ref, ID, required: true
      argument :status, GovernanceTypes::AgentChoiceStatusEnum, required: false
    end

    field :project_decision_impacts,
          GovernanceTypes::AgentChoiceImpactConnectionType,
          null: true,
          connection: false do
      description "Page AgentChoice impact assessments associated with the exact Project scope."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :outcome, GovernanceTypes::AgentChoiceImpactOutcomeEnum, required: false
      argument :project_ref, ID, required: true
    end

    field :project_decision, GovernanceTypes::ProjectDecisionType, null: true do
      description "One Decision associated with the exact Project scope."
      argument :decision_id, ID, required: true
      argument :project_ref, ID, required: true
    end

    field :project_guidance, GovernanceTypes::ProjectGuidanceType, null: true do
      description "One project-scoped guidance fact and its bounded interpretation proposals."
      argument :interpretations_after, String, required: false
      argument :interpretations_first, Integer, required: false, default_value: 20
      argument :message_id, ID, required: true
      argument :project_ref, ID, required: true
    end

    field :project_agent_choice, GovernanceTypes::ProjectAgentChoiceType, null: true do
      description "One project AgentChoice and its bounded decision-impact assessments."
      argument :choice_id, ID, required: true
      argument :impacts_after, String, required: false
      argument :impacts_first, Integer, required: false, default_value: 20
      argument :project_ref, ID, required: true
    end

    field :project_decision_impact, GovernanceTypes::ProjectAgentChoiceImpactType, null: true do
      description "One AgentChoice impact assessment associated with the exact Project scope."
      argument :assessment_id, ID, required: true
      argument :project_ref, ID, required: true
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

    field :project_candidate_checkpoints,
          DeliveryTypes::CandidateCheckpointConnectionType,
          null: true,
          connection: false do
      description "Page Candidate checkpoints submitted by any Repository member of the exact Project scope."
      argument :after, String, required: false
      argument :change_set_id, ID, required: false
      argument :checkpoint_kind, DeliveryTypes::CandidateCheckpointKindEnum, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :project_ref, ID, required: true
      argument :sort, DeliveryTypes::DeliverySortEnum, required: false, default_value: "newest_first"
    end

    field :project_verification_obligations,
          DeliveryTypes::VerificationObligationConnectionType,
          null: true,
          connection: false do
      description "Page verification obligations whose source or target belongs to the exact Project scope."
      argument :after, String, required: false
      argument :change_set_id, ID, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :project_ref, ID, required: true
      argument :sort, DeliveryTypes::DeliverySortEnum, required: false, default_value: "newest_first"
      argument :status, DeliveryTypes::VerificationObligationStatusEnum, required: false
    end

    field :project_merge_snapshots,
          DeliveryTypes::MergeSnapshotConnectionType,
          null: true,
          connection: false do
      description "Page merge snapshots produced by any Repository member of the exact Project scope."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :project_ref, ID, required: true
      argument :sort, DeliveryTypes::DeliverySortEnum, required: false, default_value: "newest_first"
    end

    field :project_release_sets,
          DeliveryTypes::ReleaseSetConnectionType,
          null: true,
          connection: false do
      description "Page ReleaseSets with at least one ordered member in the exact Project scope."
      argument :after, String, required: false
      argument :change_set_id, ID, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :project_ref, ID, required: true
      argument :sort, DeliveryTypes::DeliverySortEnum, required: false, default_value: "newest_first"
      argument :status, DeliveryTypes::ReleaseSetStatusEnum, required: false
    end

    field :project_candidate_checkpoint, DeliveryTypes::ProjectCandidateCheckpointType, null: true do
      description "One project Candidate checkpoint and one bounded semantic impact direction."
      argument :candidate_id, ID, required: true
      argument :direction, DeliveryTypes::CandidateImpactDirectionEnum, required: false, default_value: "outgoing"
      argument :first, Integer, required: false, default_value: 20
      argument :impacts_after, String, required: false
      argument :project_ref, ID, required: true
    end

    field :project_verification_obligation,
          DeliveryTypes::ProjectVerificationObligationType,
          null: true do
      description "One project-related verification obligation with bounded evidence facts."
      argument :evidence_after, String, required: false
      argument :evidence_first, Integer, required: false, default_value: 20
      argument :obligation_id, ID, required: true
      argument :project_ref, ID, required: true
    end

    field :project_merge_snapshot, DeliveryTypes::ProjectMergeSnapshotType, null: true do
      description "One project merge snapshot with candidates and bounded authorization decisions."
      argument :authorizations_after, String, required: false
      argument :authorizations_first, Integer, required: false, default_value: 20
      argument :merge_snapshot_id, ID, required: true
      argument :project_ref, ID, required: true
    end

    field :project_release_set, DeliveryTypes::ProjectReleaseSetType, null: true do
      description "One ReleaseSet whose persisted ordered members include the exact project."
      argument :project_ref, ID, required: true
      argument :release_set_id, ID, required: true
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
      cursor = Coordinator::Web::Graphql::ProjectCursor.decode_projects(
        after,
        search:,
        sort:
      )
      page = project_catalog.page(
        search:,
        sort:,
        after_scope: cursor&.fetch(:after_scope, nil),
        after_updated_at: cursor&.fetch(:after_updated_at, nil),
        first:,
        repositories_first:
      )
      {
        nodes: page.items.map { project_payload(_1) },
        page_info: {
          end_cursor: page.next_scope && Coordinator::Web::Graphql::ProjectCursor.encode_projects(
            after_scope: page.next_scope,
            after_updated_at: page.next_updated_at,
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
      cursor = Coordinator::Web::Graphql::ProjectCursor.decode_repositories(
        repositories_after,
        project_ref:
      )
      overview = project_catalog.overview(
        project_ref:,
        after_repository_id: cursor&.fetch(:after_repository_id, nil),
        after_updated_at: cursor&.fetch(:after_updated_at, nil),
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

    def project_change_sets(project_ref:, first:, after: nil, status: nil)
      filters = coordination_filters(project_ref:, first:, status:)
      cursor = coordination_cursor(after, "change-sets", filters:)
      page = coordination_dashboard.page(
        project_ref:,
        kind: "change_sets",
        first:,
        after_id: cursor&.fetch("id", nil),
        after_sort_value: cursor&.fetch("sort_value", nil),
        domain_status: status
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
        after_sort_value: cursor&.fetch("sort_value", nil),
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
      project_ref:,
      first:,
      after: nil,
      path: nil,
      resource_kind: nil,
      resource_lifecycle_status: nil
    )
      filters = resource_filters(
        project_ref:,
        first:,
        path:,
        resource_kind:,
        resource_lifecycle_status:
      )
      cursor = resource_cursor(after, "resources", filters:)
      page = project_resources_query.resources(
        project_ref:,
        first:,
        after_id: cursor&.fetch("after_id", nil),
        after_updated_at: cursor&.fetch("after_updated_at", nil),
        path:,
        resource_kind:,
        resource_lifecycle_status:
      )
      resource_connection(page, filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::ProjectResourcesQueryError => error
      raise_project_resources_query_error(error)
    end

    def project_resource(project_ref:, resource_id:)
      project_resources_query.resource(project_ref:, id: resource_id)
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::ProjectResourcesQueryError => error
      raise_project_resources_query_error(error)
    end

    def project_active_resource_leases(
      project_ref:,
      first:,
      after: nil,
      agent_id: nil,
      attempt_id: nil,
      change_set_id: nil,
      work_item_id: nil
    )
      filters = resource_filters(
        project_ref:,
        first:,
        agent_id:,
        attempt_id:,
        change_set_id:,
        work_item_id:
      )
      cursor = resource_cursor(after, "active-leases", filters:)
      page = project_resources_query.active_leases(
        project_ref:,
        first:,
        after_id: cursor&.fetch("after_id", nil),
        after_updated_at: cursor&.fetch("after_updated_at", nil),
        as_of: cursor&.fetch("as_of", nil),
        agent_id:,
        attempt_id:,
        change_set_id:,
        work_item_id:
      )
      resource_lease_connection(page, filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::ProjectResourcesQueryError => error
      raise_project_resources_query_error(error)
    end

    def project_resource_lease(project_ref:, lease_id:)
      project_resources_query.lease(project_ref:, id: lease_id)
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::ProjectResourcesQueryError => error
      raise_project_resources_query_error(error)
    end

    def project_skills(project_ref:, first:, after: nil, name: nil)
      filters = knowledge_filters(project_ref:, name:)
      cursor = Coordinator::Web::Graphql::KnowledgeBrowserCursor.decode(after, "skills", filters:)
      page = knowledge_browser.skills(
        project_ref:,
        first:,
        name:,
        after_skill_id: cursor&.fetch("after_id", nil),
        after_updated_at: cursor&.fetch("after_updated_at", nil)
      )
      skill_connection(page, filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end


    def skills(first:, after: nil, name: nil, project_scope: nil)
      filters = knowledge_filters(project_scope:, name:)
      cursor = Coordinator::Web::Graphql::KnowledgeBrowserCursor.decode(after, "skills", filters:)
      page = knowledge_browser.skills(
        scope: project_scope,
        first:,
        name:,
        after_skill_id: cursor&.fetch("after_id", nil),
        after_updated_at: cursor&.fetch("after_updated_at", nil)
      )
      skill_connection(page, filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end

    def skill(skill_id:)
      knowledge_browser.skill_by_id(skill_id:)
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end

    def skill_asset(skill_id:, path:)
      knowledge_browser.skill_asset_by_id(skill_id:, path:)
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end

    def project_skill(project_ref:, name:)
      knowledge_browser.skill(project_ref:, name:)
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end

    def project_skill_asset(project_ref:, name:, path:)
      knowledge_browser.skill_asset(project_ref:, name:, path:)
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end

    def project_artifacts(project_ref:, first:, after: nil, kind: nil, labels: nil, source_kind: nil)
      normalized_labels = labels || []
      filters = knowledge_filters(project_ref:, kind:, labels: normalized_labels, source_kind:)
      cursor = Coordinator::Web::Graphql::KnowledgeBrowserCursor.decode(after, "artifacts", filters:)
      page = knowledge_browser.artifacts(
        project_ref:,
        first:,
        kind:,
        labels: normalized_labels,
        source_kind:,
        after_updated_at: cursor&.fetch("after_updated_at", nil),
        after_observation_id: cursor&.fetch("after_id", nil)
      )
      artifact_connection(page, filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end

    def project_artifact(project_ref:, artifact_id:)
      knowledge_browser.artifact(project_ref:, artifact_id:)
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end

    def project_artifact_relationships(
      project_ref:,
      artifact_id:,
      first:,
      direction:,
      after: nil,
      relation: nil
    )
      filters = knowledge_filters(project_ref:, artifact_id:, direction:, relation:)
      cursor = Coordinator::Web::Graphql::KnowledgeBrowserCursor.decode(after, "relationships", filters:)
      detail = knowledge_browser.relationships(
        project_ref:,
        artifact_id:,
        first:,
        direction:,
        relation:,
        cursor:
      )
      return unless detail

      {
        artifact: detail.artifact,
        relationships: artifact_relation_connection(detail.relationships, filters:)
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::KnowledgeBrowserQueryError => error
      raise_knowledge_query_error(error)
    end

    def project_decisions(project_ref:, first:, after: nil, policy_status: nil, topic_id: nil)
      filters = governance_filters(project_ref:, policy_status:, topic_id:)
      cursor = Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(after, "decisions", filters:)
      page = governance_browser.decisions(
        project_ref:,
        first:,
        policy_status:,
        topic_id:,
        after_decision_id: cursor&.fetch("id", nil),
        after_updated_at: cursor&.fetch("updated_at", nil)
      )
      governance_decision_connection(page, filters:) if page
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    def project_guidance_messages(project_ref:, first:, after: nil, source: nil)
      filters = governance_filters(project_ref:, source:)
      cursor = Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(after, "guidance", filters:)
      page = governance_browser.guidance_list(
        project_ref:,
        first:,
        source:,
        after_message_id: cursor&.fetch("id", nil),
        after_updated_at: cursor&.fetch("updated_at", nil)
      )
      governance_guidance_connection(page, filters:) if page
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    def project_agent_choices(project_ref:, first:, after: nil, choice_type: nil, status: nil)
      filters = governance_filters(project_ref:, choice_type:, status:)
      cursor = Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(after, "choices", filters:)
      page = governance_browser.choices(
        project_ref:,
        first:,
        choice_type:,
        status:,
        after_choice_id: cursor&.fetch("id", nil),
        after_updated_at: cursor&.fetch("updated_at", nil)
      )
      governance_choice_connection(page, filters:) if page
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    def project_decision_impacts(project_ref:, first:, after: nil, outcome: nil)
      filters = governance_filters(project_ref:, outcome:)
      cursor = Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(after, "impacts", filters:)
      page = governance_browser.impacts(
        project_ref:,
        first:,
        outcome:,
        after_updated_at: cursor&.fetch("updated_at", nil),
        after_assessment_id: cursor&.fetch("id", nil)
      )
      governance_impact_connection(page, filters:) if page
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    def project_decision(project_ref:, decision_id:)
      governance_browser.decision(project_ref:, decision_id:)
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    def project_guidance(project_ref:, message_id:, interpretations_first:, interpretations_after: nil)
      filters = governance_filters(project_ref:, message_id:)
      detail = governance_browser.guidance(
        project_ref:,
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
        guidance: detail.guidance,
        interpretations: governance_interpretation_connection(detail.interpretations, filters:)
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    def project_agent_choice(project_ref:, choice_id:, impacts_first:, impacts_after: nil)
      filters = governance_filters(project_ref:, choice_id:)
      cursor = Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(
        impacts_after,
        "impacts",
        filters:
      )
      detail = governance_browser.choice(
        project_ref:,
        choice_id:,
        first: impacts_first,
        after_impact_updated_at: cursor&.fetch("updated_at", nil),
        after_impact_assessment_id: cursor&.fetch("id", nil)
      )
      return unless detail

      {
        choice: detail.choice,
        impacts: governance_impact_connection(detail.impacts, filters:)
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    def project_decision_impact(project_ref:, assessment_id:)
      governance_browser.impact(project_ref:, assessment_id:)
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    def command_receipts(first:, after: nil, status: nil, tool_name: nil)
      filters = governance_filters(status:, tool_name:)
      cursor = Coordinator::Web::Graphql::GovernanceBrowserCursor.decode(after, "receipts", filters:)
      page = governance_browser.receipts(
        first:,
        status:,
        tool_name:,
        after_command_id: cursor&.fetch("id", nil),
        after_updated_at: cursor&.fetch("updated_at", nil)
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

    def project_candidate_checkpoints(project_ref:, first:, sort:, after: nil, change_set_id: nil, checkpoint_kind: nil)
      filters = delivery_filters(project_ref:, change_set_id:, checkpoint_kind:, sort:)
      cursor = delivery_cursor(after, "candidates", filters:)
      page = delivery_browser.candidates(
        project_ref:,
        first:,
        sort:,
        change_set_id:,
        checkpoint_kind:,
        after_updated_at: cursor&.fetch("updated_at", nil),
        after_id: cursor&.fetch("id", nil)
      )
      delivery_timeline_connection(page, "candidates", filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def project_verification_obligations(project_ref:, first:, sort:, after: nil, change_set_id: nil, status: nil)
      filters = delivery_filters(project_ref:, change_set_id:, status:, sort:)
      cursor = delivery_cursor(after, "obligations", filters:)
      page = delivery_browser.obligations(
        project_ref:,
        first:,
        sort:,
        change_set_id:,
        status:,
        after_updated_at: cursor&.fetch("updated_at", nil),
        after_id: cursor&.fetch("id", nil)
      )
      delivery_timeline_connection(page, "obligations", filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def project_merge_snapshots(project_ref:, first:, sort:, after: nil)
      filters = delivery_filters(project_ref:, sort:)
      cursor = delivery_cursor(after, "merge-snapshots", filters:)
      page = delivery_browser.merges(
        project_ref:,
        first:,
        sort:,
        after_updated_at: cursor&.fetch("updated_at", nil),
        after_id: cursor&.fetch("id", nil)
      )
      delivery_timeline_connection(page, "merge-snapshots", filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def project_release_sets(project_ref:, first:, sort:, after: nil, change_set_id: nil, status: nil)
      filters = delivery_filters(project_ref:, change_set_id:, status:, sort:)
      cursor = delivery_cursor(after, "release-sets", filters:)
      page = delivery_browser.releases(
        project_ref:,
        first:,
        sort:,
        change_set_id:,
        status:,
        after_updated_at: cursor&.fetch("updated_at", nil),
        after_id: cursor&.fetch("id", nil)
      )
      delivery_timeline_connection(page, "release-sets", filters:)
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def project_candidate_checkpoint(project_ref:, candidate_id:, direction:, first:, impacts_after: nil)
      filters = delivery_filters(project_ref:, candidate_id:, direction:)
      detail = delivery_browser.candidate(
        project_ref:,
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
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def project_verification_obligation(
      project_ref:,
      obligation_id:,
      evidence_first:,
      evidence_after: nil
    )
      filters = delivery_filters(project_ref:, obligation_id:)
      cursor = delivery_cursor(evidence_after, "evidence", filters:)
      detail = delivery_browser.verification(
        project_ref:,
        obligation_id:,
        first: evidence_first,
        after_evidence_updated_at: cursor&.fetch("updated_at", nil),
        after_evidence_id: cursor&.fetch("id", nil)
      )
      return unless detail

      {
        obligation: detail.obligation,
        required_evidence: detail.required_evidence,
        reasons: detail.reasons,
        evidence: delivery_timeline_connection(detail.evidence, "evidence", filters:)
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def project_merge_snapshot(
      project_ref:,
      merge_snapshot_id:,
      authorizations_first:,
      authorizations_after: nil
    )
      filters = delivery_filters(project_ref:, merge_snapshot_id:)
      cursor = delivery_cursor(authorizations_after, "authorizations", filters:)
      detail = delivery_browser.merge(
        project_ref:,
        merge_snapshot_id:,
        first: authorizations_first,
        after_authorization_updated_at: cursor&.fetch("updated_at", nil),
        after_authorization_id: cursor&.fetch("id", nil)
      )
      return unless detail

      {
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
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
    rescue Coordinator::Read::Web::DeliveryBrowserQueryError => error
      raise_delivery_query_error(error)
    end

    def project_release_set(project_ref:, release_set_id:)
      delivery_browser.release(project_ref:, release_set_id:)
    rescue Coordinator::Read::Web::ProjectReference::InvalidReference => error
      raise_invalid_project_reference(error)
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
        after_updated_at: cursor&.fetch("updated_at", nil),
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
            after_repository_id: page.next_repository_id,
            after_updated_at: page.next_updated_at
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
      return unless page

      cursor = page.next_cursor
      {
        nodes: page.items,
        page_info: {
          end_cursor: cursor && Coordinator::Web::Graphql::DeliveryBrowserCursor.encode(
            kind,
            filters:,
            cursor: { "updated_at" => cursor.updated_at, "id" => cursor.id }
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

    def project_resources_query
      @project_resources_query ||= Coordinator::Read::Web::Queries::ProjectResources.new
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

    def raise_project_resources_query_error(error)
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "INVALID_INPUT", details: error.details }
      )
    end

    def resource_filters(**values)
      values.compact.transform_keys(&:to_s)
    end

    def resource_cursor(value, kind, filters:)
      Coordinator::Web::Graphql::ResourceBrowserCursor.decode(value, kind, filters:)
    end

    def resource_connection(page, filters:)
      return unless page

      {
        nodes: page.items,
        page_info: {
          end_cursor: page.next_resource_id && Coordinator::Web::Graphql::ResourceBrowserCursor.encode(
            "resources",
            filters:,
            cursor: {
              "after_id" => page.next_resource_id,
              "after_updated_at" => page.next_updated_at
            }
          ),
          has_next_page: page.has_more
        }
      }
    end

    def resource_lease_connection(page, filters:)
      return unless page

      {
        as_of: page.as_of,
        nodes: page.items,
        page_info: {
          end_cursor: page.next_lease_id && Coordinator::Web::Graphql::ResourceBrowserCursor.encode(
            "active-leases",
            filters:,
            cursor: {
              "after_id" => page.next_lease_id,
              "after_updated_at" => page.next_updated_at,
              "as_of" => page.as_of
            }
          ),
          has_next_page: page.has_more
        }
      }
    end

    def knowledge_filters(**values)
      values.compact.transform_keys(&:to_s)
    end

    def skill_connection(page, filters:)
      return unless page

      {
        nodes: page.items,
        page_info: {
          end_cursor: page.next_skill_id && Coordinator::Web::Graphql::KnowledgeBrowserCursor.encode(
            "skills",
            filters:,
            cursor: {
              "after_id" => page.next_skill_id,
              "after_updated_at" => page.next_updated_at
            }
          ),
          has_next_page: page.has_more
        }
      }
    end

    def artifact_connection(page, filters:)
      return unless page

      {
        nodes: page.items,
        page_info: {
          end_cursor: page.next_cursor &&
            Coordinator::Web::Graphql::KnowledgeBrowserCursor.encode(
              "artifacts",
              filters:,
              cursor: {
                "after_id" => page.next_cursor.observation_id,
                "after_updated_at" => page.next_cursor.updated_at
              }
            ),
          has_next_page: page.has_more
        }
      }
    end

    def artifact_relation_connection(page, filters:)
      {
        nodes: page.items,
        page_info: {
          end_cursor: page.has_more && Coordinator::Web::Graphql::KnowledgeBrowserCursor.encode(
            "relationships",
            filters:,
            cursor: page.continuation_cursor.to_h
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
        page.next_updated_at,
        "decisions",
        filters:
      )
    end

    def governance_guidance_connection(page, filters:)
      governance_connection(
        page.items,
        page.has_more,
        page.next_message_id,
        page.next_updated_at,
        "guidance",
        filters:
      )
    end

    def governance_choice_connection(page, filters:)
      governance_connection(
        page.items,
        page.has_more,
        page.next_choice_id,
        page.next_updated_at,
        "choices",
        filters:
      )
    end

    def governance_impact_connection(page, filters:)
      governance_connection(
        page.items,
        page.has_more,
        page.next_cursor&.assessment_id,
        page.next_cursor&.updated_at,
        "impacts",
        filters:
      )
    end

    def governance_interpretation_connection(page, filters:)
      governance_connection(
        page.interpretations,
        !page.next_after_revision.nil?,
        page.next_after_revision,
        nil,
        "interpretations",
        filters:
      )
    end

    def governance_receipt_connection(page, filters:)
      governance_connection(
        page.items,
        page.has_more,
        page.next_command_id,
        page.next_updated_at,
        "receipts",
        filters:
      )
    end

    def governance_connection(nodes, has_more, cursor_id, cursor_updated_at, kind, filters:)
      cursor = if kind == "interpretations"
        cursor_id
      elsif cursor_id
        { "id" => cursor_id, "updated_at" => cursor_updated_at }
      end
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
