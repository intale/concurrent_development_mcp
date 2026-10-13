# frozen_string_literal: true

module Coordinator::Read::Projections::Batches
  class UpdateGroup
    attr_reader :columns, :rows

    def initialize(columns:, rows:)
      @columns = columns.freeze
      @rows = rows.freeze
    end
  end
end
