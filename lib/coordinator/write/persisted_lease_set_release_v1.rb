# frozen_string_literal: true

module Coordinator::Write
  class PersistedLeaseSetReleaseV1 < Value
    PersistedEvent = Types.Instance(PgEventstore::Event)
    Release = Types.Instance(Events::WriteSetReleasedV1) |
              Types.Instance(Events::WriteSetReleasedV2)

    attribute :release, Release
    attribute :events, Types::Array.of(PersistedEvent).constrained(min_size: 1, max_size: 33)
  end
end
