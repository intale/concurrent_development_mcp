# frozen_string_literal: true

module Coordinator::Write
  class LatestMarkedEventReadCriteria < Value
    attribute :event_type, Types::Identifier
    attribute :marker, Types::ResourceMarker
  end
end
