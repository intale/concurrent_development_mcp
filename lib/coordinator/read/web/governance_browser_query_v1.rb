# frozen_string_literal: true

module Coordinator::Read::Web
  class GovernanceBrowserQueryV1
    class Decisions < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :topic_id, Coordinator::Shared::Types::Identifier.optional
      attribute :policy_status, Coordinator::Shared::Types::DecisionPolicyStatus.optional
      attribute :after_decision_id, Coordinator::Shared::Types::Identifier.optional
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
    end

    class GuidanceList < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :source, Coordinator::Shared::Types::GuidanceSource.optional
      attribute :after_message_id, Coordinator::Shared::Types::Identifier.optional
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
    end

    class Choices < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :choice_type, Coordinator::Shared::Types::AgentChoiceType.optional
      attribute :status, Coordinator::Shared::Types::AgentChoiceObservationStatus.optional
      attribute :after_choice_id, Coordinator::Shared::Types::Identifier.optional
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
    end

    class Impacts < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :outcome, Coordinator::Shared::Types::AgentChoiceImpactAssessmentOutcome.optional
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :after_assessment_id, Coordinator::Shared::Types::Identifier.optional
    end

    class Decision < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :decision_id, Coordinator::Shared::Types::Identifier
    end

    class Guidance < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :message_id, Coordinator::Shared::Types::Identifier
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :after_revision, Coordinator::Shared::Types::StreamRevisionCursor
    end

    class Choice < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :choice_id, Coordinator::Shared::Types::Identifier
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :after_impact_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :after_impact_assessment_id, Coordinator::Shared::Types::Identifier.optional
    end

    class Impact < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :assessment_id, Coordinator::Shared::Types::Identifier
    end

    class Receipts < Coordinator::Shared::Value
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :tool_name, Coordinator::Shared::Types::CoordinationToolName.optional
      attribute :status, Coordinator::Shared::Types::String.enum("ok").optional
      attribute :after_command_id, Coordinator::Shared::Types::Identifier.optional
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
    end

    class Receipt < Coordinator::Shared::Value
      attribute :command_id, Coordinator::Shared::Types::Identifier
    end
  end
end
