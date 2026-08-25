# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareCreateSkillPublishBatch < PrepareCreateOperationBatch
      def initialize(
        contract: Contracts::SkillPublishBatch.new,
        item_preparer: PreparePublishSkillRevision.new,
        input_digest: CommandInputDigest.new,
        manifest_builder: OperationBatches::ManifestBuilder.new
      )
        super(
          contract:,
          item_preparer:,
          target_tool: "skill_publish",
          error_label: "skill_publish_batch",
          input_digest:,
          manifest_builder:
        )
      end
    end
  end
end
