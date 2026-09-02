# frozen_string_literal: true

module Coordinator::Shared
  module Markers
    class ContractV2 < Dry::Validation::Contract
      config.validate_keys = true

      schema do
        required(:purpose).filled(:string)
        required(:components).array(
          :hash,
          min_size?: 1,
          max_size?: Types::COMPOUND_MARKER_MAXIMUM_COMPONENTS
        ) do
          required(:dimension).filled(:string)
          required(:value).value(:string)
        end
      end

      rule(:purpose) do
        key.failure("must be a lowercase marker purpose") unless Types::MARKER_PURPOSE_PATTERN.match?(value)
      end

      rule(:components) do
        normalized = []
        invalid = false

        value.each_with_index do |component, index|
          dimension = component.fetch(:dimension)
          text = component.fetch(:value)

          unless valid_utf8?(dimension) && Types::MARKER_DIMENSION_PATTERN.match?(dimension)
            key([ :components, index, :dimension ]).failure("must be a lowercase ASCII dimension")
            invalid = true
          end

          unless valid_utf8?(text)
            key([ :components, index, :value ]).failure("must be valid UTF-8")
            invalid = true
            next
          end

          normalized_text = text.encode(Encoding::UTF_8).unicode_normalize(:nfc)
          if normalized_text.match?(/\p{Cc}/)
            key([ :components, index, :value ]).failure("must not contain control characters")
            invalid = true
          end
          if !normalized_text.empty? && normalized_text.match?(/\A[[:space:]]|[[:space:]]\z/u)
            key([ :components, index, :value ]).failure("must not have surrounding whitespace")
            invalid = true
          end
          if normalized_text.start_with?("compound:")
            key([ :components, index, :value ]).failure("must not contain a nested compound marker")
            invalid = true
          end

          normalized << { dimension: dimension.encode(Encoding::UTF_8), value: normalized_text }
        end

        next if invalid

        dimensions = normalized.map { _1.fetch(:dimension) }
        key.failure("must not repeat a dimension") unless dimensions.uniq.length == dimensions.length

        encoded = CodecV2.encode(purpose: values.fetch(:purpose), components: normalized)
        if encoded.bytesize > Types::COMPOUND_MARKER_MAXIMUM_BYTES
          key.failure("selector_too_large: exceeds #{Types::COMPOUND_MARKER_MAXIMUM_BYTES} UTF-8 bytes")
        end
      end

      private

      def valid_utf8?(value)
        value.valid_encoding? && (value.encoding == Encoding::UTF_8 || value.ascii_only?)
      end
    end
  end
end
