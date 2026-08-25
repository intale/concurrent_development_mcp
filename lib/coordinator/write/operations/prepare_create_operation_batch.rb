# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareCreateOperationBatch < Dry::Operation
      def initialize(
        contract:,
        item_preparer:,
        target_tool:,
        error_label:,
        input_digest: CommandInputDigest.new,
        manifest_builder: OperationBatches::ManifestBuilder.new
      )
        @contract = contract
        @item_preparer = item_preparer
        @target_tool = target_tool
        @error_label = error_label
        @input_digest = input_digest
        @manifest_builder = manifest_builder
      end

      def call(input)
        attributes = step validate(input)
        items = step build_items(attributes.fetch(:items))
        actor_attributes = attributes.fetch(:actor)
        actor = Commands::Actor.new(kind: actor_attributes.fetch(:kind), id: actor_attributes.fetch(:id))
        encoded_byte_size = @manifest_builder.encoded_byte_size(
          command_id: attributes.fetch(:command_id),
          actor:,
          batch_id: attributes.fetch(:batch_id),
          target_tool: @target_tool,
          items:
        )
        step validate_encoded_byte_size(encoded_byte_size)

        Commands::CreateOperationBatch.new(
          command_id: attributes.fetch(:command_id),
          actor:,
          batch_id: attributes.fetch(:batch_id),
          target_tool: @target_tool,
          items:,
          manifest_digest: @manifest_builder.digest(items),
          encoded_byte_size:,
          page_size: Types::OPERATION_BATCH_PAGE_SIZE
        )
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "#{@error_label} input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_items(inputs)
        commands = []
        inputs.each do |input|
          result = @item_preparer.call(input)
          return result if result.failure?

          commands << result.value!
        end

        Success(
          commands.each_with_index.map do |command, index|
            OperationBatches::ItemV1.new(
              index:,
              command_input: @input_digest.document(command),
              canonical_input_digest: @input_digest.call(command)
            )
          end
        )
      end

      def validate_encoded_byte_size(encoded_byte_size)
        return Success(encoded_byte_size) if encoded_byte_size <= Types::OPERATION_BATCH_MAXIMUM_ENCODED_BYTES

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "#{@error_label} input is invalid",
            details: {
              encoded_byte_size: [
                "must be at most #{Types::OPERATION_BATCH_MAXIMUM_ENCODED_BYTES} bytes"
              ]
            }
          )
        )
      end
    end
  end
end
