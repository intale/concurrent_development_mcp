# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyCoordinationTaskSubmissionResolutionV1 < Value
      attribute :submission_event, Types.Instance(PgEventstore::Event)
      attribute :submission, Types.Instance(LegacyEvents::CoordinationTaskSubmittedV2)
      attribute :canonical_event, Types.Instance(PgEventstore::Event)
      attribute :canonical_submission, Types.Instance(LegacyEvents::CoordinationTaskSubmittedV2)

      def canonical?
        submission_event.id == canonical_event.id
      end
    end
  end
end
