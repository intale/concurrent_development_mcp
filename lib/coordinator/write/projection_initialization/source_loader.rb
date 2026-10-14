# frozen_string_literal: true

module Coordinator::Write
  module ProjectionInitialization
    class SourceLoader
      def initialize(event_store:)
        @event_store = event_store
      end

      def call(reference)
        definition = Definition.for_source(reference)
        return unless definition

        stream = StreamReference.new(context: definition.context, stream_name: definition.stream_name, stream_id: reference.stream_id)
        source = @event_store.read_at(stream, reference.stream_revision)
        return unless source && source.id == reference.event_id && source.type == definition.source_type

        revision = @event_store.stream_head(stream).stream_revision
        present = definition.target_types.select do |type|
          @event_store.read_latest(stream, LatestEventReadCriteria.new(event_types: [ type ], from_revision: revision))
        end
        history, corrections = [], 0
        unless present.length == definition.target_types.length
          from = 0
          loop do
            page = @event_store.read_stream_history_page(stream, StreamHistoryPageCriteria.new(
              event_types: definition.history_types, from_revision: from, to_revision: revision, page_size: 1000))
            break if page.empty?

            if definition.source_type == "DecisionActivated"
              corrections += page.length
            else
              history.concat(page)
              if history.length > definition.history_maximum_count
                raise EventHistoryLimitExceeded, "Initialization exceeded the #{definition.stream_name} source-fact bound"
              end
            end
            from = page.last.stream_revision + 1
          end
        end
        SourceState.new(definition:, stream:, source:, latest_revision: revision, existing_types: present, history:, corrections_number: corrections)
      end
    end
  end
end
