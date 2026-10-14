# frozen_string_literal: true

module Coordinator::Write::ProjectionInitialization
  class Emission < Coordinator::Write::Value
    attribute :event, Coordinator::Write::Types.Instance(Coordinator::Write::Events::Base)
    attribute :metadata, Coordinator::Write::EventMetadata
  end
end
