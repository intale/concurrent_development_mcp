# frozen_string_literal: true

module Coordinator::Read::Web::Queries
  class GovernanceBrowser
    def initialize(
      catalog_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Catalog.new,
      decision_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Decision.new,
      guidance_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Guidance.new,
      choice_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Choice.new,
      receipts_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Receipts.new,
      receipt_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::Receipt.new,
      repository: Coordinator::Read::Web::Repositories::GovernanceBrowser.new
    )
      @catalog_contract = catalog_contract
      @decision_contract = decision_contract
      @guidance_contract = guidance_contract
      @choice_contract = choice_contract
      @receipts_contract = receipts_contract
      @receipt_contract = receipt_contract
      @repository = repository
    end

    def catalog(input)
      values = validate(@catalog_contract, input)
      @repository.catalog(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::Catalog.new(
          repository_id: values[:repository_id],
          first: values[:first] || 20,
          decision_topic_id: values[:decision_topic_id],
          decision_policy_status: values[:decision_policy_status],
          after_decision_id: values[:after_decision_id],
          guidance_source: values[:guidance_source],
          after_guidance_message_id: values[:after_guidance_message_id],
          choice_type: values[:choice_type],
          choice_status: values[:choice_status],
          after_choice_id: values[:after_choice_id],
          impact_outcome: values[:impact_outcome],
          after_impact_global_position: values[:after_impact_global_position],
          after_impact_assessment_id: values[:after_impact_assessment_id]
        )
      )
    end

    def decision(input)
      values = validate(@decision_contract, input)
      @repository.decision(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::Decision.new(values.to_h)
      )
    end

    def guidance(input)
      values = validate(@guidance_contract, input)
      @repository.guidance(
        Coordinator::Read::Web::GovernanceBrowserQueryV1::Guidance.new(
          repository_id: values[:repository_id],
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
          repository_id: values[:repository_id],
          choice_id: values[:choice_id],
          first: values[:first] || 20,
          after_impact_global_position: values[:after_impact_global_position],
          after_impact_assessment_id: values[:after_impact_assessment_id]
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
          after_command_id: values[:after_command_id]
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

    def validate(contract, input)
      validated = contract.call(input)
      raise Coordinator::Read::Web::GovernanceBrowserQueryError, validated.errors.to_h if validated.failure?

      validated
    end
  end
end
