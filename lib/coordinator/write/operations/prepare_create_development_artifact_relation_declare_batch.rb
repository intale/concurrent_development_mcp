# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareCreateDevelopmentArtifactRelationDeclareBatch < PrepareCreateOperationBatch
      def initialize(
        contract: Contracts::DevelopmentArtifactRelationDeclareBatch.new,
        item_preparer: PrepareDeclareDevelopmentArtifactRelation.new,
        input_digest: CommandInputDigest.new,
        manifest_builder: OperationBatches::ManifestBuilder.new
      )
        super(
          contract:,
          item_preparer:,
          target_tool: "development_artifact_relation_declare",
          error_label: "development_artifact_relation_declare_batch",
          input_digest:,
          manifest_builder:
        )
      end
    end
  end
end
