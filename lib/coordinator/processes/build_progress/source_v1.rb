# frozen_string_literal: true

module Coordinator::Processes
  module BuildProgress
    class SourceV1 < Value
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :reference, Coordinator::Write::EventReference
      attribute :payload, Types.Instance(Coordinator::Write::Events::Base)
      attribute :change_set_id, Types::Identifier
    end
  end
end
