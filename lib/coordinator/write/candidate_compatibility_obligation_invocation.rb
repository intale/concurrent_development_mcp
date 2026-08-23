# frozen_string_literal: true

module Coordinator::Write
  class CandidateCompatibilityObligationInvocation < Value
    attribute :command, Types.Instance(Commands::CreateCandidateCompatibilityObligation)
    attribute :caused_by, Types.Instance(PgEventstore::Event)
    attribute :caused_by_reference, EventReference
  end
end
