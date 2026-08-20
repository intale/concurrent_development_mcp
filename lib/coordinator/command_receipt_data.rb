# frozen_string_literal: true

module Coordinator
  module CommandReceiptData
    class ChangeSet < Value
      attribute :change_set_id, Types::Identifier
    end

    class WorkItem < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
    end

    class Dependency < Value
      attribute :change_set_id, Types::Identifier
      attribute :dependency_id, Types::Identifier
    end

    class Attempt < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
    end

    Type = ChangeSet | WorkItem | Dependency | Attempt
  end
end
