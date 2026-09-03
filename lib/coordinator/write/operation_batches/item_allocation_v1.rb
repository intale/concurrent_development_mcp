# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class ItemAllocationV1 < Value
      attribute :command_id, Types::CommandId
      attribute :event_id, Types::UuidV7
    end
  end
end
