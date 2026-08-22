# frozen_string_literal: true

module Coordinator::Read
  class OperationGetQueryV1 < Value
    attribute :command_id, Types::Identifier
  end
end
