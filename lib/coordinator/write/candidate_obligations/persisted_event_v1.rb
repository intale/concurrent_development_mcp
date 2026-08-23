# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class PersistedEventV1 < Value
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :payload, Types.Instance(Events::Base)
      attribute :reference, EventReference
    end
  end
end
