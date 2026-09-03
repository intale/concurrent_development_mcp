# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class RegistrationPlanV2 < Value
      attribute :item, ItemV2
      attribute :actor, Commands::Actor
      attribute :register, Types::Strict::Bool
      attribute :event_id, Types::UuidV7
    end
  end
end
