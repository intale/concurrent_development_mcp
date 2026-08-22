# frozen_string_literal: true

module Coordinator::Write
  module Domain
    class EventWrite < Value
      attribute :stream, Types.Instance(StreamReference)
      attribute :event, Types.Instance(Events::Base)
    end
  end
end
