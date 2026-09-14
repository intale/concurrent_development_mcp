# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class OperationBatchSourceEvent < Dry::Validation::Contract
      EVENT_VERSIONS = {
        "OperationBatchCreated" => 2,
        "OperationBatchTargetSelected" => 1,
        "OperationBatchItemEnqueued" => 1,
        "OperationBatchItemSucceeded" => 2,
        "OperationBatchItemRejected" => 2,
        "OperationBatchItemCompletionLinked" => 1,
        "OperationBatchContinuationRequested" => 2,
        "OperationBatchCancellationRequested" => 2,
        "OperationBatchCancelled" => 2,
        "OperationBatchCompleted" => 2
      }.freeze

      params do
        required(:event_type).filled(:string, included_in?: EVENT_VERSIONS.keys)
        required(:schema_version).filled(:integer)
        required(:stream_context).filled(:string, eql?: "DevelopmentCoordination")
        required(:stream_name).filled(:string, eql?: "OperationBatch")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer)
        required(:global_position).filled(:integer)
        required(:command_id).filled(:string)
        required(:actor_kind).filled(:string)
        required(:actor_id).filled(:string)
        required(:recorded_by).filled(:string, eql?: "coordinator")
        required(:policy_version).filled(:string, eql?: "operation-batch/v2")
        optional(:manifest_digest).maybe(:string)
        optional(:page_size).maybe(:integer)
        optional(:canonical_input_digest).maybe(:string)
        optional(:encoded_byte_size).maybe(:integer)
      end

      rule(:event_type, :schema_version) do
        expected = EVENT_VERSIONS.fetch(values[:event_type])
        unless values[:schema_version] == expected
          key(:schema_version).failure("must equal #{expected} for #{values[:event_type]}")
        end
      end

      rule(:event_type, :manifest_digest, :page_size) do
        next unless values[:event_type] == "OperationBatchCreated"

        key(:manifest_digest).failure("must be present for OperationBatchCreated") unless values[:manifest_digest]
        unless values[:page_size] == Coordinator::Shared::Types::OPERATION_BATCH_PAGE_SIZE
          key(:page_size).failure("must be the bounded Batch page size")
        end
      end

      rule(:event_type, :canonical_input_digest, :encoded_byte_size) do
        next unless values[:event_type] == "OperationBatchItemEnqueued"

        unless values[:canonical_input_digest]
          key(:canonical_input_digest).failure("must be present for OperationBatchItemEnqueued")
        end
        unless values[:encoded_byte_size]&.positive?
          key(:encoded_byte_size).failure("must be positive for OperationBatchItemEnqueued")
        end
      end
    end
  end
end
