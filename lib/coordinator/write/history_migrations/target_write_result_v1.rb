# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TargetWriteResultV1 < Value
      attribute :events, Types::Array.of(Types.Instance(PgEventstore::Event)).constrained(min_size: 1)
      attribute :outcome, Types::String.enum("written", "existing", "mixed")
    end
  end
end
