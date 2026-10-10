# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class TargetPreparationV1 < Value
      HandlerPreparation = Types.Instance(DevelopmentArtifactCapturePreparationV1) |
                           Types.Instance(DevelopmentArtifactRelationPreparationV1) |
                           Types.Instance(OperationBatches::PreparationV1)

      attribute :requested_digest, Types::Sha256Digest
      attribute :terminal_event_id, Types::UuidV7
      attribute :handler_preparation, HandlerPreparation.optional
    end
  end
end
