# frozen_string_literal: true

module Coordinator::Write
  class VerificationObligationValidityScanProgressInvocation < Value
    attribute :command, Types.Instance(Commands::ProgressVerificationObligationValidityScan)
    attribute :checkpoint_event, Types.Instance(PgEventstore::Event)
    attribute :checkpoint_reference, EventReference
    attribute :caused_by, Types.Instance(PgEventstore::Event)
  end
end
