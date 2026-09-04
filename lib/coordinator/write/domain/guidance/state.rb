# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Guidance
      class State < Value
        EVENT_CLASSES = [
          Events::UserUtteranceRecordedV1,
          Events::UserUtteranceForwardedByAgentV1,
          Events::UserUtteranceRecordedV2,
          Events::UserUtteranceForwardedByAgentV2
        ].freeze

        attribute :message_id, Types::Identifier.optional

        def self.initial
          new(message_id: nil)
        end

        def self.reduce(events)
          events.reduce(initial) { |state, event| state.apply(event) }
        end

        def absent?
          message_id.nil?
        end

        def apply(event)
          return self unless EVENT_CLASSES.include?(event.class)

          self.class.new(message_id: event.message_id)
        end
      end
    end
  end
end
