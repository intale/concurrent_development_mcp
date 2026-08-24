# frozen_string_literal: true

module Coordinator::Write
  module CompatibilityAssessments
    class AssessmentInputDocumentV1 < Value
      attribute :schema, Types::String.enum("compatibility-assessment-input/v1")
      attribute :obligation_id, Types::Identifier
      attribute :binding, BindingV1
      attribute :assessment, AssessmentV1
    end
  end
end
