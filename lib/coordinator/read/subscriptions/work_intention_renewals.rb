# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class WorkIntentionRenewals < BatchRegistration
      DEFINITION = ReadModelDefinition.new(set_name: ReadModelSet::SET_NAME,
        subscription_name: "work-intention-renewals-v1",
        streams: [ Coordinator::Shared::Subscriptions::StreamFilter.new(context: "DevelopmentCoordination", stream_name: "WorkIntentionSetRenewal") ],
        event_types: Coordinator::Write::EventQueries::WORK_INTENTION_RENEWAL_HISTORY.event_types)

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end
