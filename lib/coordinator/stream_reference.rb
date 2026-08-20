# frozen_string_literal: true

module Coordinator
  class StreamReference < Value
    attribute :context, Types::String
    attribute :stream_name, Types::String
    attribute :stream_id, Types::Identifier
  end
end
