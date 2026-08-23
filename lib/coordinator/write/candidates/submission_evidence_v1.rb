# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class SubmissionEvidenceV1 < Value
      attribute :object_format, Types::GitObjectFormat
      attribute :manifest, Types.Instance(ChangeManifestV1)
      attribute :build_context, Types.Instance(BuildContextV1).optional
      attribute :actual_resources,
                Types::Array.of(Types.Instance(FileResourceV1)).constrained(min_size: 1, max_size: 32)
    end
  end
end
