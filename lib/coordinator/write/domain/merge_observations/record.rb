# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module MergeObservations
      class Record
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(history:, command:, observation_digest:, recorded_at:)
          denial = denied(history:, command:)
          return denial if denial

          authorization = history.authorization
          snapshot = history.current_evaluation.snapshot.registration
          event = Events::MergeObservedV1.new(
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
            observation_digest:,
            policy_version: command.policy_version,
            evidence_status: "attributed_unverified",
            recorded_at:
          )
          Success(
            EventPlan.new(
              writes: [ EventWrite.new(stream: @stream_factory.merge_snapshot(snapshot.merge_snapshot_id), event:) ]
            )
          )
        end

        private

        def denied(history:, command:)
          return conflict(:merge_already_observed, "Merge snapshot already has an external observation", history.existing_observation_event) if history.existing_observation
          return failure(:merge_authorization_not_found, "Exact merge authorization grant was not found") unless history.authorization
          return failure(:merge_authorization_binding_stale, "Authorization event or decision digest does not match") unless authorization_matches?(history, command)
          return stale(history.current_evaluation) unless authorization_current?(history)
          return failure(:merge_observation_mismatch, "Observed merge transition does not match the authorized snapshot", mismatch_details(history, command)) unless transition_matches?(history, command)

          nil
        end

        def authorization_matches?(history, command)
          authorization = history.authorization
          history.authorization_event == command.authorization_event &&
            authorization.decision_digest == command.authorization_decision_digest &&
            authorization.merge_snapshot_id == command.merge_snapshot_id
        end

        def authorization_current?(history)
          evaluation = history.current_evaluation
          evaluation&.granted? && evaluation == history.authorization.evaluation
        end

        def transition_matches?(history, command)
          authorization = history.authorization
          snapshot = history.current_evaluation.snapshot.registration
          base = authorization.evaluation.target_base_observation
          command.repository_id == snapshot.repository_id &&
            command.repository_id == base.repository_id &&
            command.target_branch == snapshot.target_branch &&
            command.target_branch == base.target_branch &&
            command.object_format == snapshot.object_format &&
            command.object_format == base.object_format &&
            command.target_before_commit_oid == snapshot.target_base_commit_oid &&
            command.target_before_commit_oid == base.commit_oid &&
            command.target_after_commit_oid == snapshot.merge_commit_oid
        end

        def mismatch_details(history, command)
          snapshot = history.current_evaluation.snapshot&.registration
          {
            merge_snapshot_id: command.merge_snapshot_id,
            expected_repository_id: snapshot&.repository_id,
            expected_target_branch: snapshot&.target_branch,
            expected_object_format: snapshot&.object_format,
            expected_before_commit_oid: snapshot&.target_base_commit_oid,
            expected_after_commit_oid: snapshot&.merge_commit_oid
          }
        end

        def stale(evaluation)
          failure(
            :merge_authorization_stale,
            "Merge authorization no longer matches current authoritative evidence",
            { reasons: evaluation&.reasons&.map(&:to_h) || [] }
          )
        end

        def conflict(code, message, reference)
          failure(code, message, { existing_event: reference.to_h })
        end

        def failure(code, message, details = {})
          Failure(OutcomeError.new(code:, message:, details:))
        end
      end
    end
  end
end
