# frozen_string_literal: true

module Coordinator
  module Domain
    class EventWrite < Value
      attribute :stream, Types.Instance(StreamReference)
      attribute :event, Types.Instance(Events::Base)
    end
  end
end
