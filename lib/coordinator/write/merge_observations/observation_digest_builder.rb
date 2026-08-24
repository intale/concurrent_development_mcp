# frozen_string_literal: true

module Coordinator::Write
  module MergeObservations
    class ObservationDigestBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(command:, authorization:)
        @canonical_json.sha256(
          ObservationDocumentV1.new(
            schema: "merge-observation/v1",
            merge_snapshot_id: command.merge_snapshot_id,
            authorization_event: command.authorization_event,
            authorization_decision_digest: command.authorization_decision_digest,
            snapshot_binding: authorization.snapshot_binding,
            repository_id: command.repository_id,
            target_branch: command.target_branch,
            object_format: command.object_format,
            target_before_commit_oid: command.target_before_commit_oid,
            target_after_commit_oid: command.target_after_commit_oid,
            observer: command.observer,
            run_id: command.run_id,
            observed_at: command.observed_at,
            policy_version: command.policy_version
          ).to_h
        )
      end
    end
  end
end
