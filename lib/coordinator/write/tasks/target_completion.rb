# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class TargetCompletion < Coordinator::Shared::Value
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :payload, Types.Instance(Events::CommandCompletedV1)
    end
  end
end
