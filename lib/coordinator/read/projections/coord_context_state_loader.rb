# frozen_string_literal: true

module Coordinator::Read
  module Projections
    class CoordContextStateLoader
      TERMINAL_ATTEMPT_STATUSES = %w[abandoned completed].freeze

      def call(document)
        attributes = deep_symbolize(document)
        attributes[:attempts] = attributes.fetch(:attempts, []).map do |attempt|
          compact_terminal_attempt(normalize_work_intention_set(attempt))
        end
        CoordContextStateV1.new(attributes)
      end

      private

      def compact_terminal_attempt(attempt)
        return attempt unless TERMINAL_ATTEMPT_STATUSES.include?(attempt[:status])

        attempt.merge(work_intention_set: nil)
      end

      def normalize_work_intention_set(attempt)
        return attempt if attempt.key?(:work_intention_set)

        legacy = attempt.delete(:write_set)
        return attempt.merge(work_intention_set: nil) unless legacy

        intentions = legacy.fetch(:resources).map do |resource|
          {
            intention_id: resource.fetch(:lease_id),
            resource_id: resource.fetch(:resource_id),
            resource_kind: resource.fetch(:resource_kind),
            resource_path: resource.fetch(:resource_path),
            base_blob_oid: resource[:base_blob_oid],
            mode: "exclusive",
            purpose: "Legacy Resource reservation",
            context: nil,
            fencing_token: resource.fetch(:fencing_token)
          }
        end
        attempt.merge(
          work_intention_set: {
            intention_set_id: legacy.fetch(:lease_set_id),
            repository_id: legacy.fetch(:repository_id),
            policy_version: legacy.fetch(:policy_version),
            intentions:,
            declared_at: legacy.fetch(:reserved_at),
            last_expanded_at: legacy[:last_expanded_at],
            last_renewed_at: legacy[:last_renewed_at],
            previous_expires_at: legacy[:previous_expires_at],
            expires_at: legacy.fetch(:expires_at),
            withdrawn_at: legacy[:released_at]
          }
        )
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.to_h { |key, nested| [ key.to_sym, deep_symbolize(nested) ] }
        when Array
          value.map { deep_symbolize(_1) }
        else
          value
        end
      end
    end
  end
end
