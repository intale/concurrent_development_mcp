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

    class WorkItemArguments < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
    end

    class OperationArguments < Value
      attribute :command_id, Types::Identifier
    end

    class WorkItemContextArguments < Value
      attribute :work_item_id, Types::Identifier
      attribute :after_command_id, Types::Identifier
    end

    class AttemptContextArguments < Value
      attribute :attempt_id, Types::Identifier
      attribute :after_command_id, Types::Identifier
    end

    Arguments = ChangeSetArguments |
                ContextArguments |
                AttemptArguments |
                WorkItemArguments |
                OperationArguments |
                WorkItemContextArguments |
                AttemptContextArguments

    attribute :tool, Types::Identifier
    attribute :arguments, Arguments
  end
end
