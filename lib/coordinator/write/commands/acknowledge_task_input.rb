# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class AcknowledgeTaskInput < Value
      attribute :task_id, Types::TaskId
    end
  end
end
