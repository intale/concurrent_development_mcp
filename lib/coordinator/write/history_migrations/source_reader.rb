# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class SourceReader
      # A fixed domain-contract allowlist, never a list discovered from database contents.
      EVENT_TYPES = (LegacyContractCatalog::SOURCE_CONTRACTS +
        PostRemodelContractCatalog::SOURCE_CONTRACTS).map(&:first).uniq.freeze
      SELECTION_EVENT_TYPES = %w[
        DevelopmentArtifactCreated DevelopmentArtifactContentChanged
        DevelopmentArtifactKindChanged DevelopmentArtifactLabelAdded DevelopmentArtifactLabelRemoved
        DevelopmentArtifactObservationFactLinked DevelopmentArtifactObservationRecorded
        DevelopmentArtifactScopeChanged DevelopmentArtifactSourceChanged DevelopmentArtifactTitleChanged
        CommandRegistered CommandSucceeded CommandRejected
        CoordinationTaskSubmitted CoordinationTaskExecutionStarted CoordinationTaskCompleted
      ].freeze

      def initialize(client:)
        @client = client
      end

      def head_position(to_position: nil, source_command_ids: [], source_after_position: nil)
        options = { direction: :desc, max_count: 1, filter: { event_types: event_types(source_command_ids) } }
        options[:from_position] = to_position unless to_position.nil?
        options[:to_position] = source_after_position + 1 unless source_after_position.nil?
        @client.read(
          PgEventstore::Stream.all_stream,
          options:
        ).first&.global_position
      end

      def page(criteria)
        return [] if criteria.from_position > criteria.to_position

        @client.read(
          PgEventstore::Stream.all_stream,
          options: {
            direction: :asc,
            from_position: criteria.from_position,
            to_position: criteria.to_position,
            max_count: criteria.page_size,
            filter: { event_types: event_types(criteria.source_command_ids) }
          }
        )
      end

      def stream_tail_position(event, to_position:)
        @client.read(PgEventstore::Stream.all_stream, options: {
          direction: :desc, from_position: to_position, max_count: 1,
          filter: { streams: [ { context: event.stream.context, stream_name: event.stream.stream_name, stream_id: event.stream.stream_id } ] }
        }).first&.global_position
      end

      private

      def event_types(command_ids)
        return EVENT_TYPES if command_ids.empty?

        markers = command_ids.map { "command:#{_1}" }
        submissions = @client.read(PgEventstore::Stream.all_stream, options: {
          max_count: command_ids.length + 1,
          filter: { event_types: [ { type: "CoordinationTaskSubmitted", markers: } ] }
        })
        if submissions.length > command_ids.length
          raise EventHistoryLimitExceeded, "Source selection has repeated Task submissions for one command"
        end
        task_markers = submissions.map { "task:#{_1.data.fetch('task_id')}" }
        SELECTION_EVENT_TYPES.filter_map do |type|
          lifecycle = %w[CoordinationTaskExecutionStarted CoordinationTaskCompleted].include?(type)
          next if lifecycle && task_markers.empty?

          { type:, markers: lifecycle ? task_markers : markers }
        end
      end
    end
  end
end
