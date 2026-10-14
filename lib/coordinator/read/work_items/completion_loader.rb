# frozen_string_literal: true

module Coordinator::Read::WorkItems
  class CompletionLoader
    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new)
      @event_store, @stream_factory = event_store, stream_factory
    end

    def call(work_item_id, terminal_event_id: nil)
      events = @event_store.read(@stream_factory.work_item(work_item_id), Coordinator::Write::EventQueries::WORK_ITEM_COMPLETION_FOR_PROJECTION)
      terminal = events.reverse.find { _1.type == "WorkItemCompleted" && (!terminal_event_id || _1.id == terminal_event_id) }
      selected = events.reverse.find { _1.type == "WorkItemCandidateSelected" && _1.stream_revision <= terminal.stream_revision }
      outputs = events.select { _1.type == "WorkItemOutputRecorded" && _1.stream_revision <= terminal.stream_revision }
        .map { { kind: _1.data.fetch("output_kind"), key: _1.data.fetch("output_key") } }
      Coordinator::Read::CommandResults::Source.document(selected.data).merge(
        produced_outputs: outputs, completed_at: terminal.created_at.utc.iso8601(6))
    end
  end
end
