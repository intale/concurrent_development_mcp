# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  module GovernanceTypes
  class DecisionPolicyStatusEnum < BaseEnum
    graphql_name "DecisionPolicyStatus"

    value "RECORDED", value: "recorded"
    value "ACTIVE", value: "active"
  end

  class GuidanceSourceEnum < BaseEnum
    graphql_name "GuidanceSource"

    value "MCP_CLIENT", value: "mcp_client"
    value "AGENT_FORWARDED", value: "agent_forwarded"
  end

  class AgentChoiceTypeEnum < BaseEnum
    graphql_name "AgentChoiceKind"

    value "TESTING_FRAMEWORK", value: "testing.framework"
  end

  class AgentChoiceStatusEnum < BaseEnum
    graphql_name "AgentChoiceStatus"

    value "RECORDED", value: "recorded"
    value "ACCEPTED", value: "accepted"
    value "INVALIDATED", value: "invalidated"
  end

  class AgentChoiceImpactOutcomeEnum < BaseEnum
    graphql_name "AgentChoiceImpactOutcome"

    value "STILL_VALID", value: "still_valid"
    value "INVALIDATED", value: "invalidated"
    value "NOT_APPLICABLE", value: "not_applicable"
    value "ALREADY_INVALIDATED", value: "already_invalidated"
  end

  class CommandReceiptStatusEnum < BaseEnum
    graphql_name "CommandReceiptStatus"

    value "OK", value: "ok"
  end

  class ActorType < BaseObject
    graphql_name "GovernanceActor"

    field :id, ID, null: false
    field :kind, String, null: false
  end

  class EventReferenceType < BaseObject
    graphql_name "GovernanceEventReference"

    field :id, ID, null: false, method: :event_id
    field :stream_context, String, null: false
    field :stream_id, ID, null: false
    field :stream_name, String, null: false
    field :stream_revision, Integer, null: false
    field :type, String, null: false
  end

  class DecisionValueType < BaseObject
    graphql_name "DecisionValue"

    field :action, String, null: true
    field :items, [ String ], null: true
    field :name, String, null: true
    field :schema, String, null: false
    field :target_id, ID, null: true
    field :target_kind, String, null: true
  end

  class DecisionScopeType < BaseObject
    graphql_name "DecisionScope"

    field :agent_roles, [ String ], null: false
    field :attempt_id, ID, null: true
    field :branch_selectors, [ String ], null: false
    field :candidate_id, ID, null: true
    field :change_set_id, ID, null: true
    field :contract_selectors, [ String ], null: false
    field :environments, [ String ], null: false
    field :path_selectors, [ String ], null: false
    field :repository_ids, [ ID ], null: false
    field :schema_selectors, [ String ], null: false
    field :symbol_selectors, [ String ], null: false
    field :work_item_id, ID, null: true
    field :workspace_id, ID, null: true
  end

  class DecisionConditionsType < BaseObject
    graphql_name "DecisionConditions"

    field :artifact_kinds, [ String ], null: false
    field :environments, [ String ], null: false
    field :languages, [ String ], null: false
    field :phases, [ String ], null: false
    field :repository_kinds, [ String ], null: false
    field :tags, [ String ], null: false
  end

  class DecisionAuthorityType < BaseObject
    graphql_name "DecisionAuthority"

    field :actor_id, ID, null: false
    field :role, String, null: false
  end

  class DecisionEnforcementType < BaseObject
    graphql_name "DecisionEnforcement"

    field :level, String, null: false
    field :on_violation, String, null: false
    field :retroactivity, String, null: false
  end

  class DecisionType < BaseObject
    graphql_name "GovernanceDecision"

    field :authority, DecisionAuthorityType, null: false
    field :conditions, DecisionConditionsType, null: false
    field :correction_count, Integer, null: false
    field :correction_summary, String, null: true
    field :current_at, String, null: false
    field :current_by, ActorType, null: false
    field :current_event, EventReferenceType, null: false
    field :definition_digest, String, null: false
    field :effect, String, null: false
    field :enforcement, DecisionEnforcementType, null: false
    field :id, ID, null: false, method: :decision_id
    field :interpretation_id, ID, null: false
    field :modality, String, null: false
    field :policy_status, DecisionPolicyStatusEnum, null: false
    field :rationale_summary, String, null: true
    field :recorded_at, String, null: false
    field :recorded_by, ActorType, null: false
    field :scope, DecisionScopeType, null: false
    field :source_message_id, ID, null: false
    field :statement_kind, String, null: false
    field :topic_id, String, null: false
    field :value, DecisionValueType, null: false

    def authority = object.definition.document.authority
    def conditions = object.definition.document.conditions
    def correction_summary = object.correction_rationale&.summary
    def current_at = object.current_head&.occurred_at || object.recorded.occurred_at
    def current_by = object.current_head&.actor || object.recorded.actor
    def current_event = object.current_head&.event || object.recorded.event
    def definition_digest = object.definition.digest
    def effect = object.definition.document.effect
    def enforcement = object.definition.document.enforcement
    def modality = object.definition.document.modality
    def rationale_summary = object.rationale&.summary
    def recorded_at = object.recorded.occurred_at
    def recorded_by = object.recorded.actor
    def scope = object.definition.document.scope
    def statement_kind = object.definition.document.statement_kind
    def topic_id = object.definition.document.topic.topic_id
    def value = object.definition.document.value
  end

  class GuidanceAnchorsType < BaseObject
    graphql_name "GuidanceAnchors"

    field :attempt_id, ID, null: true
    field :change_set_id, ID, null: true
    field :repository_ids, [ ID ], null: false
    field :work_item_id, ID, null: true
  end

  class ClarificationQuestionType < BaseObject
    graphql_name "InterpretationClarificationQuestion"

    field :field, String, null: false
    field :options, [ String ], null: false
    field :prompt, String, null: false
  end

  class InterpretationType < BaseObject
    graphql_name "DecisionInterpretation"

    field :actor, ActorType, null: false
    field :assessment_reasons, [ String ], null: false
    field :assessment_status, String, null: false
    field :clarification_questions, [ ClarificationQuestionType ], null: false
    field :clarification_required_at, String, null: true
    field :effect, String, null: true
    field :id, ID, null: false, method: :interpretation_id
    field :lifecycle_status, String, null: false
    field :message_id, ID, null: false
    field :modality, String, null: true
    field :policy_status, String, null: false
    field :proposed_at, String, null: false
    field :source_span_text, String, null: true
    field :statement_kind, String, null: false
    field :topic_id, String, null: false
    field :value, DecisionValueType, null: false

    def assessment_reasons = object.assessment.reasons
    def assessment_status = object.assessment.status
    def clarification_questions = object.assessment.questions
    def effect = object.proposed_decision.effect
    def modality = object.proposed_decision.modality
    def source_span_text = object.source_span&.text
    def statement_kind = object.proposed_decision.statement_kind
    def topic_id = object.proposed_decision.topic_id
    def value = object.proposed_decision.value
  end

  class GuidanceType < BaseObject
    graphql_name "ProjectGuidance"

    field :actor, ActorType, null: false
    field :anchors, GuidanceAnchorsType, null: false
    field :conversation_id, ID, null: false
    field :excerpt, String, null: false
    field :id, ID, null: false, method: :message_id
    field :policy_status, String, null: false
    field :recorded_at, String, null: false
    field :source, GuidanceSourceEnum, null: false
    field :text, String, null: false

    def excerpt
      object.text.length > 240 ? "#{object.text.slice(0, 239)}…" : object.text
    end
  end

  class AgentChoiceOptionType < BaseObject
    graphql_name "AgentChoiceOption"

    field :id, ID, null: false, method: :option_id
    field :summary, String, null: false
  end

  class AgentChoiceContextType < BaseObject
    graphql_name "AgentChoiceContext"

    field :agent_role, String, null: false
    field :attempt_id, ID, null: false
    field :change_set_id, ID, null: false
    field :environment, String, null: true
    field :language, String, null: false
    field :paths, [ String ], null: false
    field :phase, String, null: false
    field :repository_id, ID, null: false
    field :work_item_id, ID, null: false
  end

  class AgentChoiceType < BaseObject
    graphql_name "GovernanceAgentChoice"

    field :accepted_at, String, null: true
    field :accepted_by, ActorType, null: true
    field :alternatives, [ AgentChoiceOptionType ], null: false
    field :assessment_basis, String, null: true
    field :assessment_decision_ids, [ ID ], null: false
    field :assessment_warnings, [ String ], null: false
    field :choice_type, AgentChoiceTypeEnum, null: false
    field :context, AgentChoiceContextType, null: false, resolver_method: :choice_context
    field :id, ID, null: false, method: :choice_id
    field :invalidation_reason, String, null: true
    field :invalidated_at, String, null: true
    field :observation_status, AgentChoiceStatusEnum, null: false
    field :reason_summary, String, null: false
    field :recorded_at, String, null: false
    field :recorded_by, ActorType, null: false
    field :selected, AgentChoiceOptionType, null: false

    def accepted_at = object.accepted&.occurred_at
    def accepted_by = object.accepted&.actor
    def assessment_basis = object.assessment&.basis
    def assessment_decision_ids = object.assessment&.based_on_decisions&.map(&:decision_id) || []
    def assessment_warnings = object.assessment&.warnings || []
    def choice_context = object.context
    def invalidation_reason = object.invalidation&.reason
    def invalidated_at = object.invalidation&.evidence&.occurred_at
    def recorded_at = object.recorded.occurred_at
    def recorded_by = object.recorded.actor
  end

  class AgentChoiceImpactType < BaseObject
    graphql_name "AgentChoiceImpact"

    field :after_basis, String, null: false
    field :after_reason_codes, [ String ], null: false
    field :after_status, String, null: false
    field :assessed_at, String, null: false
    field :assessment_id, ID, null: false
    field :attempt_id, ID, null: false
    field :before_basis, String, null: false
    field :before_reason_codes, [ String ], null: false
    field :before_status, String, null: false
    field :choice_id, ID, null: false
    field :decision_change_kind, String, null: false
    field :decision_changed_at, String, null: false
    field :decision_id, ID, null: false
    field :outcome, AgentChoiceImpactOutcomeEnum, null: false
    field :policy_version, String, null: false
    field :reason, String, null: false

    def after_basis = object.after_evaluation.basis
    def after_reason_codes = object.after_evaluation.reason_codes
    def after_status = object.after_evaluation.status
    def assessed_at = object.assessment_evidence.occurred_at
    def before_basis = object.before_evaluation.basis
    def before_reason_codes = object.before_evaluation.reason_codes
    def before_status = object.before_evaluation.status
    def decision_change_kind = object.decision_change.change_kind
    def decision_changed_at = object.decision_change.changed_at
    def decision_id = object.decision_change.decision_id
  end

  class CommandReceiptType < BaseObject
    graphql_name "CommandReceipt"

    field :command_id, ID, null: false
    field :completed_at, String, null: false
    field :emitted_events, [ EventReferenceType ], null: false
    field :next_action_tools, [ String ], null: false
    field :receipt, ID, null: false
    field :status, CommandReceiptStatusEnum, null: false
    field :summary, String, null: false
    field :tool_name, String, null: false
    field :warnings, [ String ], null: false
  end

  class DecisionConnectionType < BaseObject
    graphql_name "GovernanceDecisionConnection"
    field :nodes, [ DecisionType ], null: false
    field :page_info, PageInfoType, null: false
  end

  class GuidanceConnectionType < BaseObject
    graphql_name "GuidanceConnection"
    field :nodes, [ GuidanceType ], null: false
    field :page_info, PageInfoType, null: false
  end

  class AgentChoiceConnectionType < BaseObject
    graphql_name "AgentChoiceConnection"
    field :nodes, [ AgentChoiceType ], null: false
    field :page_info, PageInfoType, null: false
  end

  class AgentChoiceImpactConnectionType < BaseObject
    graphql_name "AgentChoiceImpactConnection"
    field :nodes, [ AgentChoiceImpactType ], null: false
    field :page_info, PageInfoType, null: false
  end

  class InterpretationConnectionType < BaseObject
    graphql_name "DecisionInterpretationConnection"
    field :nodes, [ InterpretationType ], null: false
    field :page_info, PageInfoType, null: false
  end

  class CommandReceiptConnectionType < BaseObject
    graphql_name "CommandReceiptConnection"
    field :nodes, [ CommandReceiptType ], null: false
    field :page_info, PageInfoType, null: false
  end

  class ProjectDecisionType < BaseObject
    graphql_name "ProjectDecision"
    field :decision, DecisionType, null: false
    field :membership_bases, [ String ], null: false
  end

  class ProjectGuidanceType < BaseObject
    graphql_name "ProjectGuidanceDetail"
    field :guidance, GuidanceType, null: false
    field :interpretations, InterpretationConnectionType, null: false, connection: false
  end

  class ProjectAgentChoiceType < BaseObject
    graphql_name "ProjectAgentChoice"
    field :choice, AgentChoiceType, null: false
    field :impacts, AgentChoiceImpactConnectionType, null: false, connection: false
  end

  class ProjectAgentChoiceImpactType < BaseObject
    graphql_name "ProjectAgentChoiceImpact"
    field :impact, AgentChoiceImpactType, null: false
  end
  end
end
