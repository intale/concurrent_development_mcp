# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RemoveResource < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :resource_id, Types::ResourceId
      attribute :reason, ResourceIdentityV1::UnbindingReason
    end
  end
end
