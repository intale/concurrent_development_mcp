# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class Repositories < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "repositories-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentPlanning",
            stream_name: "Repository"
          )
        ],
        event_types: [ "RepositoryRegistered" ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
