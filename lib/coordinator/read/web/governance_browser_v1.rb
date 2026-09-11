# frozen_string_literal: true

module Coordinator::Read::Web
  class GovernanceBrowserV1
    class DecisionPage < Coordinator::Shared::Value
      attribute :items,
                Coordinator::Shared::Types::Array.of(Coordinator::Read::DecisionViewV1)
                  .constrained(max_size: 50)
      attribute :next_decision_id, Coordinator::Shared::Types::Identifier.optional
      attribute :next_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class GuidancePage < Coordinator::Shared::Value
      attribute :items,
                Coordinator::Shared::Types::Array.of(Coordinator::Read::GuidanceUtteranceV1)
                  .constrained(max_size: 50)
      attribute :next_message_id, Coordinator::Shared::Types::Identifier.optional
      attribute :next_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class AgentChoicePage < Coordinator::Shared::Value
      attribute :items,
                Coordinator::Shared::Types::Array.of(Coordinator::Read::AgentChoiceViewV1)
                  .constrained(max_size: 50)
      attribute :next_choice_id, Coordinator::Shared::Types::Identifier.optional
      attribute :next_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class ImpactCursor < Coordinator::Shared::Value
      attribute :updated_at, Coordinator::Shared::Types::Timestamp
      attribute :assessment_id, Coordinator::Shared::Types::Identifier
    end

    class ImpactPage < Coordinator::Shared::Value
      attribute :items,
                Coordinator::Shared::Types::Array.of(Coordinator::Read::AgentChoiceImpactViewV1)
                  .constrained(max_size: 100)
      attribute :next_cursor, ImpactCursor.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class DecisionDetail < Coordinator::Shared::Value
      attribute :decision, Coordinator::Read::DecisionViewV1
      attribute :membership_bases,
                Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::String)
                  .constrained(min_size: 1, max_size: 5)
    end

    class GuidanceDetail < Coordinator::Shared::Value
      attribute :guidance, Coordinator::Read::GuidanceUtteranceV1
      attribute :interpretations, Coordinator::Read::InterpretationPageV1
    end

    class ChoiceDetail < Coordinator::Shared::Value
      attribute :choice, Coordinator::Read::AgentChoiceViewV1
      attribute :impacts, ImpactPage
    end

    class ImpactDetail < Coordinator::Shared::Value
      attribute :impact, Coordinator::Read::AgentChoiceImpactViewV1
    end

    class EventReference < Coordinator::Shared::Value
      attribute :event_id, Coordinator::Shared::Types::UuidV7
      attribute :type, Coordinator::Shared::Types::Identifier
      attribute :stream_context, Coordinator::Shared::Types::Identifier
      attribute :stream_name, Coordinator::Shared::Types::Identifier
      attribute :stream_id, Coordinator::Shared::Types::Identifier
      attribute :stream_revision, Coordinator::Shared::Types::StreamRevision
    end

    class CommandReceipt < Coordinator::Shared::Value
      attribute :command_id, Coordinator::Shared::Types::Identifier
      attribute :tool_name, Coordinator::Shared::Types::CoordinationToolName
      attribute :status, Coordinator::Shared::Types::String.enum("ok")
      attribute :summary, Coordinator::Shared::Types::String
      attribute :receipt, Coordinator::Shared::Types::Identifier
      attribute :warnings,
                Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::String)
                  .constrained(max_size: 100)
      attribute :next_action_tools,
                Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::Identifier)
                  .constrained(max_size: 100)
      attribute :emitted_events,
                Coordinator::Shared::Types::Array.of(EventReference).constrained(max_size: 100)
      attribute :completed_at, Coordinator::Shared::Types::String
    end

    class ReceiptPage < Coordinator::Shared::Value
      attribute :items,
                Coordinator::Shared::Types::Array.of(CommandReceipt).constrained(max_size: 100)
      attribute :next_command_id, Coordinator::Shared::Types::Identifier.optional
      attribute :next_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class ReceiptDetail < Coordinator::Shared::Value
      attribute :receipt, CommandReceipt
    end
  end
end
