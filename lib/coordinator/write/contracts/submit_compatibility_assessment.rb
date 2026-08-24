# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class SubmitCompatibilityAssessment < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:obligation_id).filled(:string)
        required(:claim).hash do
          required(:claim_id).filled(:string)
          required(:fencing_token).filled(:integer)
        end
        required(:binding).hash do
          required(:obligation_validity_input_digest).filled(:string)
          required(:source_candidate).hash do
            required(:candidate_id).filled(:string)
            required(:head_commit_oid).filled(:string)
          end
          required(:target_candidate).hash do
            required(:candidate_id).filled(:string)
            required(:head_commit_oid).filled(:string)
          end
        end
        required(:assessment).hash do
          required(:evidence_kind).filled(
            :string,
            included_in?: Types::CANDIDATE_IMPACT_REQUIRED_EVIDENCE_KINDS
          )
          required(:producer).hash do
            required(:name).filled(:string)
            required(:version).filled(:string)
          end
          required(:run_id).filled(:string)
          required(:test_suite_digest).filled(:string)
          required(:environment_digest).filled(:string)
          required(:dependency_graph_digest).filled(:string)
          required(:result_digest).filled(:string)
          required(:conclusion).filled(
            :string,
            included_in?: Types::VERIFICATION_EVIDENCE_CONCLUSIONS
          )
          required(:findings).array(:hash) do
            required(:code).filled(:string)
            required(:severity).filled(
              :string,
              included_in?: Types::VERIFICATION_EVIDENCE_FINDING_SEVERITIES
            )
            required(:summary).filled(:string)
            optional(:path).maybe(:string)
          end
          required(:produced_at).filled(:string)
        end
      end

      rule(:command_id, :obligation_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
      end

      rule(:claim) do
        key([ :claim, :claim_id ]).failure("must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(value.fetch(:claim_id))
        key([ :claim, :fencing_token ]).failure("must be positive") unless value.fetch(:fencing_token).positive?
      end

      rule(:binding) do
        digest = value.fetch(:obligation_validity_input_digest)
        unless Types::SHA256_DIGEST_PATTERN.match?(digest)
          key([ :binding, :obligation_validity_input_digest ]).failure("must be a SHA-256 digest")
        end
        %i[source_candidate target_candidate].each do |side|
          candidate = value.fetch(side)
          unless Types::IDENTIFIER_PATTERN.match?(candidate.fetch(:candidate_id))
            key([ :binding, side, :candidate_id ]).failure("must be a valid identifier")
          end
          unless Types::GIT_OID_PATTERN.match?(candidate.fetch(:head_commit_oid))
            key([ :binding, side, :head_commit_oid ]).failure("must be a lowercase SHA-1 or SHA-256 OID")
          end
        end
      end

      rule(:assessment) do
        validate_assessment(key, value)
      end

      private

      def validate_assessment(key, assessment)
        producer = assessment.fetch(:producer)
        validate_length(key, [ :assessment, :producer, :name ], producer.fetch(:name), 100)
        validate_length(key, [ :assessment, :producer, :version ], producer.fetch(:version), 100)
        unless Types::IDENTIFIER_PATTERN.match?(assessment.fetch(:run_id))
          key.failure("run_id must be a valid identifier")
        end
        %i[test_suite_digest environment_digest dependency_graph_digest result_digest].each do |name|
          next if Types::SHA256_DIGEST_PATTERN.match?(assessment.fetch(name))

          key.failure("#{name} must be a SHA-256 digest")
        end
        unless Types::TIMESTAMP_PATTERN.match?(assessment.fetch(:produced_at))
          key.failure("produced_at must be a UTC timestamp with microseconds")
        end
        validate_findings(key, assessment.fetch(:findings))
        conclusion = assessment.fetch(:conclusion)
        if conclusion != "passed" && assessment.fetch(:findings).empty?
          key.failure("findings must explain a non-passed conclusion")
        end
      end

      def validate_findings(key, findings)
        key.failure("findings must contain at most 32 entries") if findings.length > 32
        findings.each_with_index do |finding, index|
          validate_length(key, [ :assessment, :findings, index, :code ], finding.fetch(:code), 100)
          validate_length(key, [ :assessment, :findings, index, :summary ], finding.fetch(:summary), 2_000)
          path = finding[:path]
          next if path.nil? || Types::RESOURCE_PATH_PATTERN.match?(path)

          key.failure("findings[#{index}].path must be a valid resource path")
        end
      end

      def validate_length(key, path, value, maximum)
        return if value.valid_encoding? && value.encoding == Encoding::UTF_8 && value.length.between?(1, maximum)

        key.failure("#{path.join('.')} must contain 1 to #{maximum} UTF-8 characters")
      end
    end
  end
end
