# frozen_string_literal: true

module Coordinator::Processes
  module CandidateObligations
    class RegistrySweepCheckpointV1 < Value
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :reference, Coordinator::Write::EventReference
      attribute :state, Types.Instance(Coordinator::Write::Domain::CandidateObligationScans::RegistrySweepState)
    end
  end
end
