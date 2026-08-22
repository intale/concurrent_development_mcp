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

    Arguments = ChangeSetArguments |
                AttemptArguments

    attribute :tool, Types::Identifier
    attribute :arguments, Arguments
  end
end
