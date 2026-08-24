# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class MemberLoader
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new,
        evaluator: MergeAuthorizations::Evaluator.new(event_store:)
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @evaluator = evaluator
      end

      def call(requested, position:, actor:, command_id:, evaluated_at:)
        authorization, reference = load_authorization(requested.authorization_event)
        return failure(:release_member_authorization_not_found, "Exact merge authorization grant was not found") unless authorization
        return failure(:release_member_authorization_binding_stale, "Authorization binding does not match the requested member") unless authorization_matches?(authorization, reference, requested)

        evaluation = reevaluate(authorization, actor:, command_id:, evaluated_at:)
        return stale(evaluation) unless evaluation.granted? && evaluation == authorization.evaluation

        snapshot = evaluation.snapshot.registration
        return failure(:release_member_scope_mismatch, "Release member scope does not match its authorized snapshot") unless scope_matches?(snapshot, requested)

        change_set_ids = snapshot.ordered_candidates.map(&:change_set_id).uniq
        return failure(:release_member_change_set_invalid, "Release member snapshot must contain exactly one ChangeSet") unless change_set_ids.one?

        Success(
          MemberEvidenceV1.new(
            position:,
            repository_id: snapshot.repository_id,
            target_branch: snapshot.target_branch,
            object_format: snapshot.object_format,
            merge_snapshot_id: snapshot.merge_snapshot_id,
            change_set_id: change_set_ids.sole,
            target_base_commit_oid: snapshot.target_base_commit_oid,
            merge_commit_oid: snapshot.merge_commit_oid,
            snapshot_binding: authorization.snapshot_binding,
            authorization_event: reference,
            authorization_decision_digest: authorization.decision_digest,
            ordered_candidates: snapshot.ordered_candidates
          )
        )
      end

      private

      def load_authorization(expected_reference)
        stream = @stream_factory.merge_authorization(expected_reference.stream_id)
        physical = @event_store.read_at(stream, expected_reference.stream_revision)
        return [ nil, nil ] unless physical && event_reference(physical) == expected_reference
        return [ nil, nil ] unless physical.type == "MergeAuthorizationGranted"

        [ load_event(physical), event_reference(physical) ]
      end

      def authorization_matches?(authorization, reference, requested)
        reference == requested.authorization_event &&
          authorization.merge_snapshot_id == requested.merge_snapshot_id &&
          authorization.snapshot_binding == requested.snapshot_binding &&
          authorization.decision_digest == requested.authorization_decision_digest
      end

      def reevaluate(authorization, actor:, command_id:, evaluated_at:)
        command = Commands::RequestMergeAuthorization.new(
          command_id:,
          actor:,
          merge_snapshot_id: authorization.merge_snapshot_id,
          snapshot_binding: authorization.snapshot_binding,
          target_base_observation: authorization.evaluation.target_base_observation,
          expected_impact_policy: authorization.expected_impact_policy,
          policy_version: authorization.policy_version
        )
        @evaluator.call(command, decided_at: evaluated_at)
      end

      def scope_matches?(snapshot, requested)
        snapshot.merge_snapshot_id == requested.merge_snapshot_id &&
          snapshot.repository_id == requested.repository_id &&
          snapshot.target_branch == requested.target_branch &&
          snapshot.object_format == requested.object_format
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def stale(evaluation)
        failure(
          :release_member_authorization_stale,
          "Merge authorization no longer matches current authoritative evidence",
          reasons: evaluation.reasons.map(&:to_h)
        )
      end

      def failure(code, message, details = {})
        Failure(OutcomeError.new(code:, message:, details:))
      end
    end
  end
end
