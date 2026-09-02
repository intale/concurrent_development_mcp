# frozen_string_literal: true

module Coordinator::Shared
  class CanonicalMarkerComponentBuilder
    MAXIMUM_VALUE_BYTES = 400

    def initialize(canonical_json: CanonicalJson.new)
      @canonical_json = canonical_json
    end

    def call(dimension:, value:)
      chunks(@canonical_json.encode(value)).each_with_index.map do |chunk, index|
        "#{dimension}-#{index.to_s.rjust(3, '0')}:#{chunk}"
      end
    end

    private

    def chunks(value)
      value.each_char.each_with_object([]) do |character, result|
        result << +"" if result.empty? || result.last.bytesize + character.bytesize > MAXIMUM_VALUE_BYTES
        result.last << character
      end
    end
  end
end
