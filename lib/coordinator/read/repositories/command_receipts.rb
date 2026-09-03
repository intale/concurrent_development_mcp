# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class CommandReceipts
      def fetch(command_id)
        record = Coordinator::Read::CommandReceipt.find_by(command_id:)
        return unless record

        build(record)
      end

      def fetch_by_request_id(request_id)
        record = Coordinator::Read::CommandReceipt.find_by(request_id:)
        return unless record

        build(record)
      end

      def fetch_many(command_ids)
        results = fetch_index(command_ids)
        command_ids.filter_map { results[_1] }
      end

      def fetch_index(command_ids)
        Coordinator::Read::CommandReceipt.where(command_id: command_ids).index_by(&:command_id)
          .transform_values { build(_1) }
      end

      def store(event:, result:)
        Coordinator::Read::CommandReceipt.create!(
          command_id: event.stream.stream_id,
          request_id: result.command_id,
          command_stream_revision: event.stream_revision,
          tool_name: result.tool_name,
          canonical_input_digest: result.canonical_input_digest,
          status: result.status,
          summary: result.summary,
          receipt: result.receipt,
          completion: result.to_h,
          completed_at_domain: result.completed_at,
          created_at: event.created_at,
          updated_at: event.created_at
        )
      end

      private

      def build(record)
        CommandResults::ResultV1.new(deep_symbolize(record.completion))
      end

      def deep_symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, deep_symbolize(nested) ] }
        when Array then value.map { deep_symbolize(_1) }
        else value
        end
      end
    end
  end
end
