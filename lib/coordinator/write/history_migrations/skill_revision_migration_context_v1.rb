# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class SkillRevisionMigrationContextV1 < Value
      attribute :skill_stream, StreamReference
      attribute :revision_stream, StreamReference
      attribute :asset_streams,
                Types::Array.of(Types.Instance(StreamReference)).constrained(
                  max_size: Types::SKILL_ASSET_MAXIMUM_COUNT
                )

      def skill_id
        skill_stream.stream_id
      end

      def skill_revision_id
        revision_stream.stream_id
      end
    end
  end
end
