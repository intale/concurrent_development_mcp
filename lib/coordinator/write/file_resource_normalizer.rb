# frozen_string_literal: true

module Coordinator::Write
  class FileResourceNormalizer
    include Dry::Monads[:result]

    MAX_PATH_BYTES = 1_024

    def initialize(canonical_json: CanonicalJson.new)
      @canonical_json = canonical_json
    end

    def call(repository_id:, kind:, path:, base_blob_oid:, scope: nil)
      return failure(:unsupported_resource_kind, "Resource kind is not supported", kind:) unless kind == "file"

      normalized_path = normalize_path(path)
      return normalized_path if normalized_path.failure?

      build_resource(
        repository_id:,
        path: normalized_path.value!,
        base_blob_oid:,
        scope:
      )
    end

    private

    def normalize_path(path)
      unless path.valid_encoding? && path.encoding == Encoding::UTF_8
        return failure(:resource_path_encoding, "Resource path must be valid UTF-8", path:)
      end
      return failure(:resource_path_empty, "Resource path cannot be empty", path:) if path.empty?
      if path.bytesize > MAX_PATH_BYTES
        return failure(:resource_path_too_long, "Resource path exceeds 1024 UTF-8 bytes", path:)
      end
      if /[\u0000-\u001f\u007f]/.match?(path)
        return failure(:resource_path_control_character, "Resource path contains a control character", path:)
      end

      separated = path.tr("\\", "/")
      if separated.start_with?("/") || /\A[A-Za-z]:\//.match?(separated)
        return failure(:resource_path_absolute, "Resource path must be relative", path:)
      end

      segments = reduce_segments(separated, original_path: path)
      return segments if segments.failure?

      normalized = segments.value!.join("/")
      return failure(:resource_path_empty, "Resource path cannot be empty", path:) if normalized.empty?
      if normalized.bytesize > MAX_PATH_BYTES
        return failure(:resource_path_too_long, "Normalized resource path exceeds 1024 UTF-8 bytes", path:)
      end

      Success(normalized)
    end

    def reduce_segments(path, original_path:)
      segments = []

      path.split("/").each do |segment|
        next if segment.empty? || segment == "."

        if segment == ".."
          return failure(:resource_path_escape, "Resource path escapes its repository", path: original_path) if segments.empty?

          segments.pop
        else
          segments << segment
        end
      end

      Success(segments)
    end

    def build_resource(repository_id:, path:, base_blob_oid:, scope:)
      document = resource_key_document(repository_id:, path:, scope:)

      Success(
        FileResourceV1.new(
          kind: document.kind,
          path: document.path,
          base_blob_oid:,
          resource_key: resource_key(document),
          resource_key_hash: @canonical_json.sha256(document.to_h),
          policy_version: document.policy_version
        )
      )
    end

    def resource_key_document(repository_id:, path:, scope:)
      return ResourceKeyDocumentV2.new(
        schema: ResourceKeyDocumentV2::POLICY_VERSION,
        policy_version: ResourceKeyDocumentV2::POLICY_VERSION,
        scope:,
        repository_id:,
        kind: "file",
        path:
      ) if scope

      ResourceKeyDocumentV1.new(
        schema: ResourceKeyDocumentV1::POLICY_VERSION,
        policy_version: ResourceKeyDocumentV1::POLICY_VERSION,
        repository_id:,
        kind: "file",
        path:
      )
    end

    def resource_key(document)
      prefix = "scope:#{document.scope}:" if document.respond_to?(:scope)

      "#{prefix}repo:#{document.repository_id}:file:#{document.path}"
    end

    def failure(code, message, **details)
      Failure(OutcomeError.new(code:, message:, details:))
    end
  end
end
