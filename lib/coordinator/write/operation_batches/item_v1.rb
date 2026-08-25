# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class ItemV1 < Value
      Target = CommandInputDocuments::PublishSkillRevisionV1 |
               CommandInputDocuments::CaptureDevelopmentArtifactV1 |
               CommandInputDocuments::DeclareDevelopmentArtifactRelationV1

      attribute :index, Types::OperationBatchItemIndex
      attribute :command_input, Target
      attribute :canonical_input_digest, Types::Sha256Digest
    end
  end
end
