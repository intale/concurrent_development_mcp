# frozen_string_literal: true

module Coordinator::Shared
  class CanonicalJson
    CONTRACT = "coordinator-canonical-json/v1"
    MAX_NESTING = 64
    MAX_SAFE_INTEGER = (2**53) - 1
    MIN_SAFE_INTEGER = -MAX_SAFE_INTEGER

    GENERATOR_OPTIONS = {
      allow_nan: false,
      ascii_only: false,
      max_nesting: MAX_NESTING,
      array_nl: "",
      object_nl: "",
      indent: "",
      space: "",
      space_before: ""
    }.freeze

    class Error < ArgumentError; end
    class CycleDetected < Error; end
    class DuplicateKey < Error; end
    class InvalidString < Error; end
    class NestingExceeded < Error; end
    class UnsafeInteger < Error; end
    class UnsupportedValue < Error; end

    def encode(value)
      normalized = normalize(value, depth: 0, ancestors: {})

      JSON.generate(normalized, GENERATOR_OPTIONS)
    rescue JSON::GeneratorError, JSON::NestingError => error
      raise Error, error.message
    end

    def sha256(value)
      "sha256:#{OpenSSL::Digest::SHA256.hexdigest(encode(value))}"
    end

    private

    def normalize(value, depth:, ancestors:)
      raise NestingExceeded, "canonical JSON exceeds #{MAX_NESTING} levels" if depth > MAX_NESTING

      case value
      when nil, true, false
        value
      when String
        normalize_string(value)
      when Integer
        normalize_integer(value)
      when Array
        normalize_array(value, depth:, ancestors:)
      when Hash
        normalize_object(value, depth:, ancestors:)
      else
        raise UnsupportedValue, "unsupported canonical JSON value: #{value.class}"
      end
    end

    def normalize_array(value, depth:, ancestors:)
      within_compound(value, ancestors:) do
        value.map { |element| normalize(element, depth: depth + 1, ancestors:) }
      end
    end

    def normalize_object(value, depth:, ancestors:)
      within_compound(value, ancestors:) do
        normalized = value.each_with_object({}) do |(key, element), result|
          string_key = normalize_key(key)
          raise DuplicateKey, "duplicate canonical JSON key: #{string_key.inspect}" if result.key?(string_key)

          result[string_key] = normalize(element, depth: depth + 1, ancestors:)
        end

        normalized.sort_by { |key, _element| key.b }.to_h
      end
    end

    def normalize_key(key)
      case key
      when String
        normalize_string(key)
      when Symbol
        normalize_string(key.name)
      else
        raise UnsupportedValue, "unsupported canonical JSON object key: #{key.class}"
      end
    end

    def normalize_string(value)
      unless value.encoding == Encoding::UTF_8 || (value.encoding == Encoding::US_ASCII && value.ascii_only?)
        raise InvalidString, "canonical JSON strings must be UTF-8"
      end

      utf8 = value.encode(Encoding::UTF_8)
      raise InvalidString, "canonical JSON strings must contain valid UTF-8" unless utf8.valid_encoding?

      utf8
    rescue EncodingError => error
      raise InvalidString, error.message
    end

    def normalize_integer(value)
      unless (MIN_SAFE_INTEGER..MAX_SAFE_INTEGER).cover?(value)
        raise UnsafeInteger,
          "canonical JSON integer must be between #{MIN_SAFE_INTEGER} and #{MAX_SAFE_INTEGER}"
      end

      value
    end

    def within_compound(value, ancestors:)
      identity = value.object_id
      raise CycleDetected, "canonical JSON values must be acyclic" if ancestors.key?(identity)

      ancestors[identity] = true
      yield
    ensure
      ancestors.delete(identity) if identity
    end
  end
end
