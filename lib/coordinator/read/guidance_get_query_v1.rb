# frozen_string_literal: true

module Coordinator::Read
  class GuidanceGetQueryV1 < Value
    attribute :message_id, Types::Identifier
  end
end
