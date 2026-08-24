# frozen_string_literal: true

module Coordinator::Write
  class VerificationObligationInvalidationInvocation < Value
    attribute :command, Types.Instance(Commands::InvalidateVerificationObligation)
    attribute :caused_by_event, Types.Instance(PgEventstore::Event)
    attribute :caused_by_reference, EventReference
  end
end
