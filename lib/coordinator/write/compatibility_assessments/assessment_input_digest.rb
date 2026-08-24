# frozen_string_literal: true

module Coordinator::Write
  module CompatibilityAssessments
    class AssessmentInputDigest
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(command)
        @canonical_json.sha256(document(command).to_h)
      end

      def document(command)
        AssessmentInputDocumentV1.new(
          schema: "compatibility-assessment-input/v1",
          obligation_id: command.obligation_id,
          binding: command.binding,
          assessment: command.assessment
        )
      end
    end
  end
end
