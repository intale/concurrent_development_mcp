# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CandidateSourceFactV1 < Value
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :payload, Types.Instance(Events::Base)
    end
  end
end
