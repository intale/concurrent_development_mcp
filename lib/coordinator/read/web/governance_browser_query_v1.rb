# frozen_string_literal: true

module Coordinator::Read::Web
  class GovernanceBrowserQueryV1
    class Catalog < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :decision_topic_id, Coordinator::Shared::Types::Identifier.optional
      attribute :decision_policy_status, Coordinator::Shared::Types::DecisionPolicyStatus.optional
      attribute :after_decision_id, Coordinator::Shared::Types::Identifier.optional
      attribute :guidance_source, Coordinator::Shared::Types::GuidanceSource.optional
      attribute :after_guidance_message_id, Coordinator::Shared::Types::Identifier.optional
      attribute :choice_type, Coordinator::Shared::Types::AgentChoiceType.optional
      attribute :choice_status, Coordinator::Shared::Types::AgentChoiceObservationStatus.optional
      attribute :after_choice_id, Coordinator::Shared::Types::Identifier.optional
      attribute :impact_outcome,
                Coordinator::Shared::Types::AgentChoiceImpactAssessmentOutcome.optional
      attribute :after_impact_global_position, Coordinator::Shared::Types::GlobalPosition.optional
      attribute :after_impact_assessment_id, Coordinator::Shared::Types::Identifier.optional
    end

    class Decision < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :decision_id, Coordinator::Shared::Types::Identifier
    end

    class Guidance < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :message_id, Coordinator::Shared::Types::Identifier
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :after_revision, Coordinator::Shared::Types::StreamRevisionCursor
    end

    class Choice < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :choice_id, Coordinator::Shared::Types::Identifier
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :after_impact_global_position, Coordinator::Shared::Types::GlobalPosition.optional
      attribute :after_impact_assessment_id, Coordinator::Shared::Types::Identifier.optional
    end

    class Receipts < Coordinator::Shared::Value
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :tool_name, Coordinator::Shared::Types::CoordinationToolName.optional
      attribute :status, Coordinator::Shared::Types::String.enum("ok").optional
      attribute :after_command_id, Coordinator::Shared::Types::Identifier.optional
    end

    class Receipt < Coordinator::Shared::Value
      attribute :command_id, Coordinator::Shared::Types::Identifier
    end
  end
end
