# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    module Text
      module_function

      def valid?(value, max_size:)
        return false unless value.is_a?(String)
        return false unless value.encoding == Encoding::UTF_8 || (value.encoding == Encoding::US_ASCII && value.ascii_only?)
        return false unless value.valid_encoding?
        return false if value.include?("\0") || value.strip.empty?

        value.length <= max_size
      end
    end
  end
end
