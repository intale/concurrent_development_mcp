# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class ManifestBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def digest(items)
        @canonical_json.sha256(items.map(&:to_h))
      end

      def encoded_byte_size(command_id:, actor:, batch_id:, target_tool:, items:)
        @canonical_json.encode(
          command_id:,
          actor: actor.to_h,
          batch_id:,
          target_tool:,
          items: items.map(&:to_h)
        ).bytesize
      end

      def item_encoded_byte_size(input)
        @canonical_json.encode(input.to_h).bytesize
      end
    end
  end
end
