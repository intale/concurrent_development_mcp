# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TargetWriteResultV1 < Value
      attribute :events, Types::Array.of(Types.Instance(PgEventstore::Event))
      attribute :outcome, Types::String.enum("written", "existing", "mixed", "skipped")
    end
  end
end
