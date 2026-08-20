# frozen_string_literal: true

module Coordinator
  module Subscriptions
    class StreamFilter < Value
      attribute :context, Types::Identifier
      attribute :stream_name, Types::Identifier
    end
  end
end
