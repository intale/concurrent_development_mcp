# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareSubmitCompatibilityAssessment < Dry::Operation
      def initialize(contract: Contracts::SubmitCompatibilityAssessment.new)
        @contract = contract
      end

      def call(input)
        attributes = step validate(input)

        step build_command(attributes)
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "SubmitCompatibilityAssessment input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_command(attributes)
        actor = attributes.fetch(:actor)
        assessment = attributes.fetch(:assessment)
        findings = assessment.fetch(:findings).map do |finding|
          CompatibilityAssessments::FindingV1.new(
            code: finding.fetch(:code),
            severity: finding.fetch(:severity),
            summary: finding.fetch(:summary),
            path: finding[:path]
          )
        end
        Success(
          Commands::SubmitCompatibilityAssessment.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            obligation_id: attributes.fetch(:obligation_id),
            claim: CompatibilityAssessments::ClaimV1.new(attributes.fetch(:claim)),
            binding: CompatibilityAssessments::BindingV1.new(attributes.fetch(:binding)),
            assessment: CompatibilityAssessments::AssessmentV1.new(
              assessment.merge(findings:)
            )
          )
        )
      end
    end
  end
end
