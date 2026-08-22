# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class ReloadedLeaseExpirySource < Dry::Validation::Contract
      params do
        required(:locator).value(Types.Instance(LeaseExpirySourceLocatorV1))
        required(:source).value(Types.Instance(LeaseExpirySource))
      end

      rule(:locator, :source) do
        locator = values[:locator]
        source = values[:source]
        matches = source.reference.event_id == locator.source_event_id &&
          source.reference.stream_id == locator.resource_key_hash &&
          source.reference.stream_revision == locator.stream_revision
        key(:source).failure("must exactly match the scheduled source locator") unless matches
      end
    end
  end
end
