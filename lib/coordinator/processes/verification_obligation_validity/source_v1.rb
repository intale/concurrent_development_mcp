# frozen_string_literal: true

module Coordinator::Processes
  module VerificationObligationValidity
    class SourceV1 < Value
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :reference, Coordinator::Write::EventReference
      attribute :payload, Types.Instance(Coordinator::Write::Events::Base)
    end
  end
end
