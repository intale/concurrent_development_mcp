# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class CommandTerminalV1 < EventMetadata
      attribute :emitted_events,
                Types::Array.of(EventReference).constrained(max_size: 128).default([].freeze)
      attribute :rejection, Tasks::DomainErrorV1::Type.optional.default(nil)
    end
  end
end
