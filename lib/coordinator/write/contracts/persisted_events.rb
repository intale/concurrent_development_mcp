# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class PersistedEvents < Dry::Validation::Contract
      params do
        required(:events).filled(:array).each(Types.Instance(PgEventstore::Event))
      end

      rule(:events).each do
        key.failure("must have a persisted stream and revision") if value.stream.nil? || value.stream_revision.nil?
      end
    end
  end
end
