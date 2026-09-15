# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TransformedFactV1 < Value
      attribute :target_stream, StreamReference
      attribute :event, Types.Instance(Events::Base)
      attribute :markers, Types::Array.of(Types::ResourceMarker).constrained(max_size: 32)
      attribute :step_name, Types::Identifier
    end
  end
end
