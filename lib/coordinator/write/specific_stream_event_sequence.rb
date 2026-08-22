# frozen_string_literal: true

module Coordinator::Write
  module SpecificStreamEventSequence
    def self.merge(left, right)
      merged = []
      left_index = 0
      right_index = 0

      while left_index < left.length && right_index < right.length
        if left.fetch(left_index).stream_revision <= right.fetch(right_index).stream_revision
          merged << left.fetch(left_index)
          left_index += 1
        else
          merged << right.fetch(right_index)
          right_index += 1
        end
      end

      merged.concat(left.drop(left_index)).concat(right.drop(right_index)).freeze
    end
  end
end
