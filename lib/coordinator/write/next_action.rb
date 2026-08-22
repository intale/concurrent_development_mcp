# frozen_string_literal: true

module Coordinator::Write
  class NextAction < Value
    class ChangeSetArguments < Value
      attribute :change_set_id, Types::Identifier
    end

    class AttemptArguments < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
    end

    class GuidanceArguments < Value
      attribute :message_id, Types::Identifier
    end

    class InterpretationListArguments < Value
      attribute :message_id, Types::Identifier
    end

    Arguments = ChangeSetArguments |
                AttemptArguments |
                GuidanceArguments |
                InterpretationListArguments

    attribute :tool, Types::Identifier
    attribute :arguments, Arguments
  end
end
