# frozen_string_literal: true

module Coordinator::Write
  class FileResourceNormalizer
    include Dry::Monads[:result]

    MAX_PATH_BYTES = 1_024
    MAX_PATH_COMPONENTS = 32
    SUPPORTED_KINDS = %w[file directory].freeze

    def initialize(canonical_json: CanonicalJson.new)
      @canonical_json = canonical_json
    end

    def call(repository_id:, kind:, path:, base_blob_oid:, scope: nil)
      unless SUPPORTED_KINDS.include?(kind)
        return failure(:unsupported_resource_kind, "Resource kind is not supported", kind:)
      end

      normalized_path = normalize_path(path)
      return normalized_path if normalized_path.failure?

      build_resource(
        repository_id:,
        kind:,
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
      if path.include?("\\")
        return failure(
          :resource_path_backslash,
          "Git resource paths use '/' separators; literal backslashes are unsupported",
          path:
        )
      end

      if path.start_with?("/") || /\A[A-Za-z]:\//.match?(path)
        return failure(:resource_path_absolute, "Resource path must be relative", path:)
      end
      if path.end_with?("/")
        return failure(:resource_path_trailing_separator, "Resource path cannot end with '/'", path:)
      end

      segments = path.split("/", -1)
      if segments.any?(&:empty?)
        return failure(:resource_path_empty_component, "Resource path cannot contain empty components", path:)
      end
      if segments.include?(".")
        return failure(:resource_path_dot_component, "Resource path cannot contain '.' components", path:)
      end
      if segments.include?("..")
        return failure(:resource_path_parent_component, "Resource path cannot contain '..' components", path:)
      end
      if segments.length > MAX_PATH_COMPONENTS
        return failure(
          :resource_path_too_deep,
          "Resource path exceeds 32 components",
          path:,
          component_count: segments.length
        )
      end

      Success(path)
    end

    def build_resource(repository_id:, kind:, path:, base_blob_oid:, scope:)
      document = resource_key_document(repository_id:, kind:, path:, scope:)

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

    def resource_key_document(repository_id:, kind:, path:, scope:)
      return ResourceKeyDocumentV3.new(
        schema: ResourceKeyDocumentV3::POLICY_VERSION,
        policy_version: ResourceKeyDocumentV3::POLICY_VERSION,
        scope:,
        repository_id:,
        kind:,
        path:
      ) if scope

      ResourceKeyDocumentV1.new(
        schema: ResourceKeyDocumentV1::POLICY_VERSION,
        policy_version: ResourceKeyDocumentV1::POLICY_VERSION,
        repository_id:,
        kind:,
        path:
      )
    end

    def resource_key(document)
      prefix = "scope:#{document.scope}:" if document.respond_to?(:scope)

      "#{prefix}repo:#{document.repository_id}:#{document.kind}:#{document.path}"
    end

    def failure(code, message, **details)
      Failure(OutcomeError.new(code:, message:, details:))
    end
  end
end
