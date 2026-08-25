# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareCreateDevelopmentArtifactCaptureBatch < PrepareCreateOperationBatch
      def initialize(
        contract: Contracts::DevelopmentArtifactCaptureBatch.new,
        item_preparer: PrepareCaptureDevelopmentArtifact.new,
        input_digest: CommandInputDigest.new,
        manifest_builder: OperationBatches::ManifestBuilder.new
      )
        super(
          contract:,
          item_preparer:,
          target_tool: "development_artifact_capture",
          error_label: "development_artifact_capture_batch",
          input_digest:,
          manifest_builder:
        )
      end
    end
  end
end
