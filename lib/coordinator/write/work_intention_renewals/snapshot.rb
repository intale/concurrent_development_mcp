# frozen_string_literal: true

module Coordinator::Write
  module WorkIntentionRenewals
    class Snapshot < Value
      attribute :state, State
      attribute :events, Types::Array.of(Types.Instance(PgEventstore::Event)).constrained(max_size: 66)

      def latest_revision
        events.last&.stream_revision || :no_stream
      end
    end
  end
end
