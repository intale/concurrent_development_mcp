# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyCoordinationTaskSubmissionResolutionV1 < Value
      Submission =
        Types.Instance(LegacyEvents::CoordinationTaskSubmittedV2) |
        Types.Instance(PostRemodelEvents::CoordinationTaskSubmittedV3)

      attribute :submission_event, Types.Instance(PgEventstore::Event)
      attribute :submission, Submission
      attribute :canonical_event, Types.Instance(PgEventstore::Event)
      attribute :canonical_submission, Submission
      attribute :command_identity_event, Types.Instance(PgEventstore::Event)

      def canonical?
        submission_event.id == canonical_event.id
      end
    end
  end
end
