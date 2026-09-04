# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligations
    class LoadedDefinitionV2 < Value
      attribute :definition, DefinitionV2
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :reference, EventReference
    end
  end
end
