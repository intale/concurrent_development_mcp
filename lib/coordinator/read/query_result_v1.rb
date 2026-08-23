# frozen_string_literal: true

module Coordinator::Read
  class QueryResultV1 < Value
    class EmptyData < Value
    end

    class DomainError < Value
      attribute :code, Types::String
      attribute :message, Types::String
      attribute :details, Types::Hash
    end

    class OperationData < Value
      attribute :result, Coordinator::Write::CommandReceiptData::Type
      attribute :emitted_events,
                Types::Array.of(Coordinator::Write::EventReference).constrained(min_size: 1)
    end

    class ContextData < Value
      attribute :scope, ContextTokenDocument::Scope
      attribute :context, Projections::CoordContextStateV1
      attribute :blockers, Types::Array.of(ContextBlockerV1).constrained(max_size: 500)
      attribute :last_processed_at, Types::Timestamp
    end

    class NotModifiedData < Value
      attribute :scope, ContextTokenDocument::Scope
      attribute :last_processed_at, Types::Timestamp
    end

    class GuidanceData < Value
      attribute :guidance, GuidanceUtteranceV1
    end

    class InterpretationPageData < Value
      attribute :page, InterpretationPageV1
    end

    class DecisionData < Value
      attribute :decision, DecisionViewV1
    end

    class DecisionContextData < Value
      attribute :decision_context, DecisionResolution::ContextV1
    end

    class AgentChoiceData < Value
      attribute :choice, AgentChoiceViewV1
    end

    class AgentChoiceImpactPageData < Value
      attribute :page, AgentChoiceImpactPageV1
    end

    class CandidateData < Value
      attribute :candidate, CandidateViewV1
    end

    class CandidatePageData < Value
      attribute :page, CandidatePageV1
    end

    class CandidateImpactData < Value
      attribute :page, CandidateImpactPageV1
    end

    Data = EmptyData |
           DomainError |
           OperationData |
           ContextData |
           NotModifiedData |
           GuidanceData |
           InterpretationPageData |
           DecisionData |
           DecisionContextData |
           AgentChoiceData |
           AgentChoiceImpactPageData |
           CandidateData |
           CandidatePageData |
           CandidateImpactData
    Action = Coordinator::Write::NextAction | NextAction

    attribute :status, Types::String.enum(
      "ok",
      "not_found",
      "invalid",
      "not_modified",
      "conflict",
      "limit_reached"
    )
    attribute :summary, Types::String
    attribute :command_id, Types::Identifier.optional
    attribute :receipt, Types::Identifier.optional
    attribute :context_token, Types::Sha256Digest.optional
    attribute :data, Data
    attribute :warnings, Types::Array.of(Types::String).constrained(max_size: 100)
    attribute :next_actions, Types::Array.of(Action).constrained(max_size: 100)
  end
end
