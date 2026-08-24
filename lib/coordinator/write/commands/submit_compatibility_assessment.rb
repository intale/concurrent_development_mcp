# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class SubmitCompatibilityAssessment < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :obligation_id, Types::Identifier
      attribute :claim, CompatibilityAssessments::ClaimV1
      attribute :binding, CompatibilityAssessments::BindingV1
      attribute :assessment, CompatibilityAssessments::AssessmentV1
    end
  end
end
