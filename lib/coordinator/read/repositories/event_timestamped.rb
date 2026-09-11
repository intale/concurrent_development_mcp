# frozen_string_literal: true

module Coordinator::Read::Repositories
  module EventTimestamped
    private

    def create_from_event(model, event:, attributes:)
      save_from_event(model.new, event:, attributes:)
    end

    def save_from_event(record, event:, attributes: {})
      record.assign_attributes(attributes)
      record.updated_at = projection_timestamp.call(current: record.updated_at, event:)
      record.save!(touch: false)
      record
    end

    def projection_timestamp
      @projection_timestamp ||= Coordinator::Read::ProjectionTimestamp.new
    end
  end
end
