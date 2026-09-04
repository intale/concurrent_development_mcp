# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module MergeAuthorizations
      class Decide
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(command:, evaluation:, authorization_id:)
          event_class = evaluation.granted? ?
            Events::MergeAuthorizationGrantedV2 : Events::MergeAuthorizationDeniedV2
          event = event_class.new(
            authorization_id:,
            merge_snapshot_id: command.merge_snapshot_id,
            snapshot_binding: command.snapshot_binding,
            evaluation:
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
