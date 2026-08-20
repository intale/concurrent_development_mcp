# frozen_string_literal: true

module Coordinator
  class PgStreamFactory
    def call(reference)
      PgEventstore::Stream.new(**reference.to_h)
    end
  end
end
