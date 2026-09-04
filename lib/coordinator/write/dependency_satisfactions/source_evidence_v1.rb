# frozen_string_literal: true

module Coordinator::Write
  module DependencySatisfactions
    class SourceEvidenceV1 < Value
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :reference, EventReference
      attribute :payload, Types.Instance(Events::Base)
      attribute :producer_state, Domain::WorkItems::State
      attribute :release_state, Domain::ReleaseSets::LifecycleStateV2.optional
    end
  end
end
