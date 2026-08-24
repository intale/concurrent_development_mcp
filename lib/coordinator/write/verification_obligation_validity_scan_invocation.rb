# frozen_string_literal: true

module Coordinator::Write
  class VerificationObligationValidityScanInvocation < Value
    attribute :command, Types.Instance(Commands::StartVerificationObligationValidityScan)
    attribute :source_event, Types.Instance(PgEventstore::Event)
    attribute :source_reference, EventReference
  end
end
