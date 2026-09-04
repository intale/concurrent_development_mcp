# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligations
    class PersistedDefinitionV2 < Value
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :definition, DefinitionV2
      attribute :reference, EventReference
    end
  end
end
