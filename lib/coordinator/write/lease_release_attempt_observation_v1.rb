# frozen_string_literal: true

module Coordinator::Write
  class LeaseReleaseAttemptObservationV1 < Value
    attribute :state, Types.Instance(Domain::Attempts::State)
    attribute :release_event, Types.Instance(PgEventstore::Event).optional
  end
end
