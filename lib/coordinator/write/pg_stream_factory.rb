# frozen_string_literal: true

module Coordinator::Write
  class PgStreamFactory
    def call(reference)
      PgEventstore::Stream.new(**reference.to_h)
    end
  end
end
