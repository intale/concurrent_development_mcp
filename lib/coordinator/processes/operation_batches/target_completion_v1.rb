# frozen_string_literal: true

module Coordinator::Processes
  module OperationBatches
    class TargetCompletionV1 < Coordinator::Shared::Value
      attribute :event, Coordinator::Shared::Types::Any
      attribute :payload, Coordinator::Write::Events::CommandCompletedV1
      attribute :reference, Coordinator::Write::EventReference
    end
  end
end
