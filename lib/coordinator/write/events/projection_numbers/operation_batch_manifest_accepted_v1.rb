# frozen_string_literal: true

module Coordinator::Write::Events
  module ProjectionNumbers
    class OperationBatchManifestAcceptedV1 < Base
      contract type: "OperationBatchManifestAccepted", version: 1

      attribute :batch_id, Coordinator::Write::Types::UuidV7
    end
  end
end
