# frozen_string_literal: true

module Coordinator::Shared
  module Markers
    class CodecV2
      include Dry::Monads[:result]

      PREFIX = "compound"
      VERSION = "v2"

      class ErrorV2 < Value
        attribute :code, Types::Symbol.enum(:invalid_selector, :selector_too_large)
        attribute :message, Types::String
        attribute :errors, Types::Hash
      end

      class ParseError < StandardError; end

      class << self
        def normalize_components(components)
          components.map do |component|
            {
              dimension: component.fetch(:dimension).encode(Encoding::UTF_8),
              value: component.fetch(:value).encode(Encoding::UTF_8).unicode_normalize(:nfc)
            }
          end.sort_by { _1.fetch(:dimension).b }
        end

        def encode(purpose:, components:)
          normalized = normalize_components(components)
          normalized.each_with_object("#{PREFIX}:#{purpose}:#{VERSION}") do |component, marker|
            wire = "#{component.fetch(:dimension)}=#{component.fetch(:value)}"
            marker << "|#{wire.bytesize}:#{wire}"
          end
        end
      end

      def initialize(contract: ContractV2.new)
        @contract = contract
      end

      def call(purpose:, components:)
        validation = @contract.call(purpose:, components:)
        return Failure(error_for(validation.errors.to_h)) if validation.failure?

        attributes = validation.to_h
        normalized = self.class.normalize_components(attributes.fetch(:components))
        definition = DefinitionV2.new(
          purpose: attributes.fetch(:purpose),
          components: normalized.map { ComponentV2.new(_1) }
        )
        marker = self.class.encode(purpose: definition.purpose, components: normalized)

        Success(EncodedV2.new(definition:, marker:))
      end

      def decode(marker)
        purpose, components = parse(marker)
        result = call(purpose:, components:)
        return result if result.failure?
        return result if result.value!.marker == marker

        Failure(invalid_selector(marker: [ "must use canonical marker encoding" ]))
      rescue ParseError => error
        Failure(invalid_selector(marker: [ error.message ]))
      end

      private

      def parse(marker)
        raise ParseError, "must be valid UTF-8" unless marker.encoding == Encoding::UTF_8 && marker.valid_encoding?

        match = /\A#{PREFIX}:([a-z][a-z0-9-]{0,63}):#{VERSION}\|/.match(marker)
        raise ParseError, "must use the compound marker v2 prefix" unless match

        [ match[1], parse_components(marker.byteslice(match[0].bytesize..)) ]
      end

      def parse_components(remainder)
        bytes = remainder.b
        components = []

        until bytes.empty?
          length_text, separator, tail = bytes.partition(":")
          unless separator == ":" && length_text.match?(/\A(?:0|[1-9][0-9]*)\z/)
            raise ParseError, "contains an invalid component byte length"
          end

          length = length_text.to_i
          wire = tail.byteslice(0, length)
          raise ParseError, "contains a truncated component" unless wire&.bytesize == length

          bytes = tail.byteslice(length..).to_s
          unless bytes.empty? || bytes.start_with?("|")
            raise ParseError, "contains an invalid component boundary"
          end
          bytes = bytes.byteslice(1..).to_s unless bytes.empty?

          wire = wire.force_encoding(Encoding::UTF_8)
          raise ParseError, "contains an invalid UTF-8 component" unless wire.valid_encoding?

          dimension, equals, value = wire.partition("=")
          raise ParseError, "contains a component without a dimension separator" unless equals == "="

          components << { dimension:, value: }
        end

        raise ParseError, "must contain at least one component" if components.empty?

        components
      end

      def error_for(errors)
        serialized = errors.inspect
        return selector_too_large(errors) if serialized.include?("selector_too_large")

        invalid_selector(errors)
      end

      def selector_too_large(errors)
        ErrorV2.new(code: :selector_too_large, message: "Compound marker exceeds its byte limit", errors:)
      end

      def invalid_selector(errors)
        ErrorV2.new(code: :invalid_selector, message: "Compound marker definition is invalid", errors:)
      end
    end
  end
end
