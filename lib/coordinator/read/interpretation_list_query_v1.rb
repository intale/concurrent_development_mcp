# frozen_string_literal: true

module Coordinator::Read
  class InterpretationListQueryV1 < Value
    attribute :message_id, Types::Identifier
    attribute :after_revision, Types::StreamRevisionCursor
    attribute :limit, Types::InterpretationPageLimit
  end
end
