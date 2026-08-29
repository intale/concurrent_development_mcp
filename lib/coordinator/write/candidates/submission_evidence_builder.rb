# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class SubmissionEvidenceBuilder < Dry::Operation
      def initialize(
        resource_normalizer: FileResourceNormalizer.new,
        canonical_json: CanonicalJson.new,
        uniqueness_contract: Contracts::CandidateEvidenceUniqueness.new
      )
        @resource_normalizer = resource_normalizer
        @canonical_json = canonical_json
        @uniqueness_contract = uniqueness_contract
      end

      def call(attributes)
        object_format = attributes.fetch(:base_commit_oid).length == 40 ? "sha1" : "sha256"
        collector = collector(attributes.fetch(:actor), attributes.dig(:change_manifest, :collector_version))
        files = step normalize_manifest_files(attributes.fetch(:repository_id), attributes.dig(:change_manifest, :files))
        resources = actual_resources(files)
        build_context_parts = step normalize_build_context(attributes)
        step validate_uniqueness(files, resources, build_context_parts)

        manifest = build_manifest(attributes, object_format:, collector:, files:)
        build_context = build_context_parts && build_context(attributes, object_format:, parts: build_context_parts)
        SubmissionEvidenceV1.new(
          object_format:,
          manifest:,
          build_context:,
          actual_resources: collapse_resources(resources)
        )
      rescue CanonicalJson::Error => error
        step Failure(
          OutcomeError.new(
            code: :invalid_candidate_evidence,
            message: "Candidate evidence cannot be canonically encoded",
            details: { reason: error.message }
          )
        )
      end

      private

      def collector(actor, collector_version)
        EvidenceCollectorV1.new(
          kind: actor.fetch(:kind),
          id: actor.fetch(:id),
          collector_version:
        )
      end

      def normalize_manifest_files(repository_id, files)
        normalized = []
        files.each do |file|
          old_path = step normalize_path(repository_id, file[:old_path], file[:old_blob_oid])
          new_path = step normalize_path(repository_id, file[:new_path], nil)
          normalized << ManifestFileV1.new(
            status: file.fetch(:status),
            old_path:,
            new_path:,
            old_blob_oid: file[:old_blob_oid],
            new_blob_oid: file[:new_blob_oid],
            old_mode: file[:old_mode],
            new_mode: file[:new_mode]
          )
        end
        Success(normalized.sort_by { @canonical_json.encode(_1.to_h).b })
      end

      def normalize_build_context(attributes)
        context = attributes[:build_context]
        return Success(nil) unless context

        inputs = []
        context.fetch(:inputs).each do |input|
          path = step normalize_path(attributes.fetch(:repository_id), input.fetch(:path), input.fetch(:blob_oid))
          inputs << BuildInputV1.new(kind: input.fetch(:kind), path:, blob_oid: input.fetch(:blob_oid))
        end
        environment = context.fetch(:environment).map do |entry|
          EnvironmentEntryV1.new(name: entry.fetch(:name), value: entry.fetch(:value))
        end
        Success(
          NormalizedBuildContextV1.new(
            collector: collector(attributes.fetch(:actor), context.fetch(:collector_version)),
            inputs: inputs.sort_by { [ _1.path.b, _1.kind.b, _1.blob_oid.b ] },
            environment: environment.sort_by { [ _1.name.b, _1.value.b ] },
            dependency_graph_digest: context[:dependency_graph_digest],
            test_environment_digest: context[:test_environment_digest]
          )
        )
      end

      def normalize_path(repository_id, path, base_blob_oid)
        return Success(nil) unless path

        result = @resource_normalizer.call(
          repository_id:,
          kind: "file",
          path:,
          base_blob_oid:
        )
        return result if result.failure?

        Success(result.value!.path)
      end

      def actual_resources(files)
        files.flat_map do |file|
          resource_specs(file).map do |path, base_blob_oid|
            ActualResourceV2.new(kind: "file", path:, base_blob_oid:)
          end
        end
      end

      def resource_specs(file)
        case file.status
        when "added", "copied"
          [ [ file.new_path, nil ] ]
        when "renamed"
          [ [ file.old_path, file.old_blob_oid ], [ file.new_path, nil ] ]
        else
          [ [ file.old_path, file.old_blob_oid ] ]
        end
      end

      def validate_uniqueness(files, resources, build_context_parts)
        result = @uniqueness_contract.call(
          manifest_files: files.map(&:to_h),
          actual_resource_evidence: resources.map do
            { path: _1.path, base_blob_oid: _1.base_blob_oid }
          end,
          build_input_keys: build_context_parts ? build_context_parts.inputs.map(&:path) : [],
          environment_names: build_context_parts ? build_context_parts.environment.map(&:name) : []
        )
        return Success() if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_candidate_evidence,
            message: "Candidate evidence violates normalized uniqueness or cardinality rules",
            details: result.errors.to_h
          )
        )
      end

      def collapse_resources(resources)
        resources.group_by(&:path).values.map(&:first).sort_by { _1.path.b }
      end

      def build_manifest(attributes, object_format:, collector:, files:)
        document = ChangeManifestDocumentV1.new(
          schema: ChangeManifestDocumentV1::SCHEMA,
          candidate_id: attributes.fetch(:candidate_id),
          repository_id: attributes.fetch(:repository_id),
          target_branch: attributes.fetch(:target_branch),
          object_format:,
          base_commit_oid: attributes.fetch(:base_commit_oid),
          head_commit_oid: attributes.fetch(:head_commit_oid),
          files:
        )
        ChangeManifestV1.new(
          policy_version: ChangeManifestDocumentV1::SCHEMA,
          digest: @canonical_json.sha256(document.to_h),
          files:,
          collector:
        )
      end

      def build_context(attributes, object_format:, parts:)
        document = BuildContextDocumentV1.new(
          schema: BuildContextDocumentV1::SCHEMA,
          candidate_id: attributes.fetch(:candidate_id),
          repository_id: attributes.fetch(:repository_id),
          object_format:,
          head_commit_oid: attributes.fetch(:head_commit_oid),
          inputs: parts.inputs,
          environment: parts.environment,
          dependency_graph_digest: parts.dependency_graph_digest,
          test_environment_digest: parts.test_environment_digest
        )
        BuildContextV1.new(
          policy_version: BuildContextDocumentV1::SCHEMA,
          digest: @canonical_json.sha256(document.to_h),
          inputs: parts.inputs,
          environment: parts.environment,
          dependency_graph_digest: parts.dependency_graph_digest,
          test_environment_digest: parts.test_environment_digest,
          collector: parts.collector
        )
      end
    end
  end
end
