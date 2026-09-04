# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AttemptBaseSnapshotRecordedV1 < Base
      contract type: "AttemptBaseSnapshotRecorded", version: 1

      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :object_format, Types::GitObjectFormat
      attribute :commit_oid, Types::GitOid
    end
  end
end
