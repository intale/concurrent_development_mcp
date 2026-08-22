# frozen_string_literal: true

module Coordinator::Read
  class NextAction < Value
    class ChangeSetArguments < Value
      attribute :change_set_id, Types::Identifier
    end

    class WorkItemArguments < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
    end

    class AttemptArguments < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
    end

    Arguments = ChangeSetArguments | WorkItemArguments | AttemptArguments

    attribute :tool, Types::Identifier
    attribute :arguments, Arguments
  end
end
