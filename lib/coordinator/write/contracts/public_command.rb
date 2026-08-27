# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class PublicCommand < Dry::Validation::Contract
      params do
        required(:command_id).value(Types::PublicCommandId)
      end
    end
  end
end
