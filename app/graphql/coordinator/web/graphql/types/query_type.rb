# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class QueryType < BaseObject
    graphql_name "Query"
    description "Read-only access to the latest available coordination projections."

    field :projects, ProjectConnectionType, null: false, connection: false do
      description "List projects in one exact caller-chosen scope in stable Repository-ID order."
      argument :after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :scope, String, required: true
    end

    field :project_coordination, ProjectCoordinationType, null: true do
      description "Latest available coordination facts for one registered project."
      argument :blocking, Boolean, required: false
      argument :change_sets_after, String, required: false
      argument :dependencies_after, String, required: false
      argument :first, Integer, required: false, default_value: 20
      argument :presentation_statuses, [ CoordinationPresentationStatusEnum ], required: false
      argument :repository_id, ID, required: true
      argument :work_item_sort, WorkItemSortEnum, required: false, default_value: "work_item_id_asc"
      argument :work_items_after, String, required: false
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

    def projects(scope:, first:, after: nil)
      query = Coordinator::Read::Queries::RepositoryList.new.call(
        scope:,
        after_repository_id: Coordinator::Web::Graphql::ProjectCursor.decode(after),
        limit: first
      ).value!
      raise_query_error(query) unless query.status == "ok"

      page = query.data.page
      {
        nodes: page.items,
        page_info: {
          end_cursor: page.next_repository_id &&
            Coordinator::Web::Graphql::ProjectCursor.encode(page.next_repository_id),
          has_next_page: page.has_more
        }
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    end

    def project_coordination(
      repository_id:,
      first:,
      work_item_sort:,
      blocking: nil,
      change_sets_after: nil,
      dependencies_after: nil,
      presentation_statuses: nil,
      work_items_after: nil
    )
      dashboard = Coordinator::Read::Web::Queries::CoordinationDashboard.new.call(
        repository_id:,
        first:,
        change_set_offset: Coordinator::Web::Graphql::DashboardCursor.decode(
          change_sets_after,
          "change-sets"
        ),
        work_item_offset: Coordinator::Web::Graphql::DashboardCursor.decode(
          work_items_after,
          "work-items"
        ),
        dependency_offset: Coordinator::Web::Graphql::DashboardCursor.decode(
          dependencies_after,
          "dependencies"
        ),
        presentation_statuses: presentation_statuses || [],
        work_item_sort:,
        blocking:
      )
      return unless dashboard

      {
        project: dashboard.project,
        change_sets: connection(dashboard.change_sets, "change-sets"),
        work_items: connection(dashboard.work_items, "work-items"),
        dependencies: connection(dashboard.dependencies, "dependencies")
      }
    rescue Coordinator::Web::Graphql::InvalidCursor => error
      raise GraphQL::ExecutionError.new(error.message, extensions: { code: "INVALID_CURSOR" })
    rescue Coordinator::Read::Web::CoordinationDashboardQueryError => error
      raise GraphQL::ExecutionError.new(
        error.message,
        extensions: { code: "INVALID_INPUT", details: error.details }
      )
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
    end

    def command_receipt(command_id:)
      governance_browser.receipt(command_id:)&.receipt
    rescue Coordinator::Read::Web::GovernanceBrowserQueryError => error
      raise_governance_query_error(error)
    end

    private

    def connection(page, kind)
      {
        nodes: page.items,
        page_info: {
          end_cursor: page.next_offset && Coordinator::Web::Graphql::DashboardCursor.encode(kind, page.next_offset),
          has_next_page: page.has_more
        }
      }
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

    def raise_query_error(result)
      raise GraphQL::ExecutionError.new(
        result.data.message,
        extensions: { code: result.data.code.upcase, details: result.data.details }
      )
    end
  end
end
