# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class GuidanceMessageIdentityV1 < Value
      SourceMessage = Types.Instance(Events::UserUtteranceRecordedV1) |
        Types.Instance(Events::UserUtteranceForwardedByAgentV1)

      attribute :source_message, SourceMessage
      attribute :source_event, Types.Instance(PgEventstore::Event)
      attribute :target_message_id, Types::UuidV7
    end
  end
end
