# frozen_string_literal: true

module Coordinator::Write
  class PersistedLeaseSetRelease < Value
    PersistedEvent = Types.Instance(PgEventstore::Event)

    attribute :release, Types.Instance(Events::WriteSetReleasedV2)
    attribute :events, Types::Array.of(PersistedEvent).constrained(min_size: 1, max_size: 33)
  end
end
