# frozen_string_literal: true

module Coordinator
  class NextAction < Value
    class ChangeSetArguments < Value
      attribute :change_set_id, Types::Identifier
    end

    class ContextArguments < Value
      attribute :change_set_id, Types::Identifier
      attribute :after_command_id, Types::Identifier
    end

    class AttemptArguments < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
    end

    Arguments = ChangeSetArguments | ContextArguments | AttemptArguments

    attribute :tool, Types::Identifier
    attribute :arguments, Arguments
  end
end
