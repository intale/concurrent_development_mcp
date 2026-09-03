# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class ItemV2 < Value
      Target = CommandInputDocuments::PublishSkillRevisionV2 |
               CommandInputDocuments::CaptureDevelopmentArtifactV2 |
               CommandInputDocuments::DeclareDevelopmentArtifactRelationV1

      attribute :index, Types::OperationBatchItemIndex
      attribute :request_id, Types::RequestId
      attribute :command_input, Target
      attribute :canonical_input_digest, Types::Sha256Digest

      def command_id
        command_input.command_id
      end
    end
  end
end
