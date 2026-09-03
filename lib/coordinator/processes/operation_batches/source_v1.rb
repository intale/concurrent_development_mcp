# frozen_string_literal: true

module Coordinator::Processes
  module OperationBatches
    class SourceV1 < Coordinator::Shared::Value
      Payload = Coordinator::Shared::Types.Instance(Coordinator::Write::Events::OperationBatchCreatedV2) |
                Coordinator::Shared::Types.Instance(Coordinator::Write::Events::OperationBatchContinuationRequestedV2) |
                Coordinator::Shared::Types.Instance(Coordinator::Write::Events::OperationBatchCancellationRequestedV2)

      attribute :event, Coordinator::Shared::Types::Any
      attribute :payload, Payload
      attribute :reference, Coordinator::Write::EventReference
    end
  end
end
