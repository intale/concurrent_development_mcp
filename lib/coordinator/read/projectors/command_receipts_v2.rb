# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class CommandReceiptsV2
      def initialize(facts:, assembler: CommandResults::Assembler.new(facts:))
        @facts, @assembler = facts, assembler
      end

      def call(events)
        patches = Projections::Batches::ColumnPatches.new(identity_columns: [ :command_id ])
        events.each do |event|
          source = @facts.call(event)
          next unless source

          result = @assembler.call(source)
          attributes = {
            command_id: source.command_id, request_id: result.fetch(:command_id),
            command_stream_revision: event.stream_revision, tool_name: result.fetch(:tool_name),
            canonical_input_digest: result.fetch(:canonical_input_digest), status: result.fetch(:status), summary: result.fetch(:summary),
            receipt: result.fetch(:receipt), completion: result, completed_at_domain: result.fetch(:completed_at)
          }
          patches.insert(attributes.merge(created_at: event.created_at, updated_at: event.created_at))
          patches.assign(attributes)
          patches.touch({ command_id: source.command_id }, time: event.created_at)
        end
        Repositories::BatchWriter.new(model: CommandReceipt, patches:).call
      end
    end
  end
end
