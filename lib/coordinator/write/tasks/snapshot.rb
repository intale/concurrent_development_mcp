# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class Snapshot < Value
      attribute :state, Types.Instance(Domain::CoordinationTasks::State)
      attribute :latest_revision, Types::Integer.optional
    end
  end
end
