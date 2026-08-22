# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class UntilEventConditionV1 < Value
      attribute :event_type, Types::Identifier
      attribute :stream_context, Types::Identifier
      attribute :stream_name, Types::Identifier
      attribute :stream_id, Types::Identifier
    end
  end
end
