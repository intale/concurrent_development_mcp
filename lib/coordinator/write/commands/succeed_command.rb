# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class SucceedCommand < Value
      attribute :command_id, Types::CommandId
    end
  end
end
