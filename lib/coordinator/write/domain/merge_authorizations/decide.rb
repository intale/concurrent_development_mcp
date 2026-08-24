# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module MergeAuthorizations
      class Decide
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(command:, evaluation:, authorization_id:, input_digest:, decision_digest:, decided_at:)
          event_class = evaluation.granted? ?
            Events::MergeAuthorizationGrantedV1 : Events::MergeAuthorizationDeniedV1
          event = event_class.new(
            authorization_id:,
            merge_snapshot_id: command.merge_snapshot_id,
            policy_version: command.policy_version,
            snapshot_binding: command.snapshot_binding,
            expected_impact_policy: command.expected_impact_policy,
            evaluation:,
            input_digest:,
            decision_digest:,
            decided_at:
          )
          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.merge_authorization(authorization_id),
                  event:
                )
              ]
            )
          )
        end
      end
    end
  end
end
