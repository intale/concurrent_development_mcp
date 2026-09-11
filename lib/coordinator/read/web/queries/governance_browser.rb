# frozen_string_literal: true

module Coordinator::Read::Web::Queries
  class GovernanceBrowser
    def initialize(
      decisions_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Decisions.new,
      guidance_list_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::GuidanceList.new,
      choices_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Choices.new,
      impacts_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Impacts.new,
      decision_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Decision.new,
      guidance_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Guidance.new,
      choice_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Choice.new,
      impact_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Impact.new,
      receipts_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Receipts.new,
      receipt_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Receipt.new,
      project_reference: Coordinator::Read::Web::ProjectReference.new,
      repository: Coordinator::Read::Web::Repositories::GovernanceBrowser.new
    )
      @decisions_contract = decisions_contract
      @guidance_list_contract = guidance_list_contract
      @choices_contract = choices_contract
      @impacts_contract = impacts_contract
      @decision_contract = decision_contract
      @guidance_contract = guidance_contract
      @choice_contract = choice_contract
      @impact_contract = impact_contract
      @receipts_contract = receipts_contract
      @receipt_contract = receipt_contract
      @project_reference = project_reference
      @repository = repository
    end

    def decisions(input)
      values = validate(@decisions_contract, input)
      @repository.decisions(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::Decisions.new(
          project_scope: project_scope(values),
          first: values[:first] || 20,
          topic_id: values[:topic_id],
          policy_status: values[:policy_status],
          after_decision_id: values[:after_decision_id],
          after_updated_at: values[:after_updated_at]
        )
      )
    end

    def guidance_list(input)
      values = validate(@guidance_list_contract, input)
      @repository.guidance_list(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::GuidanceList.new(
          project_scope: project_scope(values),
          first: values[:first] || 20,
          source: values[:source],
          after_message_id: values[:after_message_id],
          after_updated_at: values[:after_updated_at]
        )
      )
    end

    def choices(input)
      values = validate(@choices_contract, input)
      @repository.choices(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::Choices.new(
          project_scope: project_scope(values),
          first: values[:first] || 20,
          choice_type: values[:choice_type],
          status: values[:status],
          after_choice_id: values[:after_choice_id],
          after_updated_at: values[:after_updated_at]
        )
      )
    end

    def impacts(input)
      values = validate(@impacts_contract, input)
      @repository.impacts(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::Impacts.new(
          project_scope: project_scope(values),
          first: values[:first] || 20,
          outcome: values[:outcome],
          after_updated_at: values[:after_updated_at],
          after_assessment_id: values[:after_assessment_id]
        )
      )
    end

    def decision(input)
      values = validate(@decision_contract, input)
      @repository.decision(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::Decision.new(
          project_scope: project_scope(values),
          decision_id: values[:decision_id]
        )
      )
    end

    def guidance(input)
      values = validate(@guidance_contract, input)
      @repository.guidance(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::Guidance.new(
          project_scope: project_scope(values),
          message_id: values[:message_id],
          first: values[:first] || 20,
          after_revision: values[:after_revision] || -1
        )
      )
    end

    def choice(input)
      values = validate(@choice_contract, input)
      @repository.choice(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::Choice.new(
          project_scope: project_scope(values),
          choice_id: values[:choice_id],
          first: values[:first] || 20,
          after_impact_updated_at: values[:after_impact_updated_at],
          after_impact_assessment_id: values[:after_impact_assessment_id]
        )
      )
    end

    def impact(input)
      values = validate(@impact_contract, input)
      @repository.impact(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::Impact.new(
          project_scope: project_scope(values),
          assessment_id: values[:assessment_id]
        )
      )
    end

    def receipts(input)
      values = validate(@receipts_contract, input)
      @repository.receipts(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::Receipts.new(
          first: values[:first] || 20,
          tool_name: values[:tool_name],
          status: values[:status],
          after_command_id: values[:after_command_id],
          after_updated_at: values[:after_updated_at]
        )
      )
    end

    def receipt(input)
      values = validate(@receipt_contract, input)
      @repository.receipt(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::Receipt.new(values.to_h)
      )
    end

    private

    def project_scope(values)
      @project_reference.decode(values[:project_ref])
    end

    def validate(contract, input)
      validated = contract.call(input)
      raise Coordinator::Read::Web::GovernanceBrowserQueryError, validated.errors.to_h if validated.failure?

      validated
    end
  end
end
