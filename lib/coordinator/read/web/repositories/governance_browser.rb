# frozen_string_literal: true

module Coordinator::Read::Web::Repositories
  class GovernanceBrowser
    def initialize(
      decisions: Coordinator::Read::Repositories::DecisionGovernance.new,
      utterances: Coordinator::Read::Repositories::UserUtterances.new,
      interpretations: Coordinator::Read::Repositories::DecisionInterpretations.new,
      choices: Coordinator::Read::Repositories::AgentChoices.new,
      impacts: Coordinator::Read::Repositories::AgentChoiceImpacts.new
    )
      @decisions = decisions
      @utterances = utterances
      @interpretations = interpretations
      @choices = choices
      @impacts = impacts
    end

    def catalog(query)
      project = find_project(query.repository_id)
      return unless project

      Coordinator::Read::Web::GovernanceBrowserV1::Catalog.new(
        project: build_project(project),
        decisions: @decisions.page(
          Coordinator::Read::DecisionListQueryV1.new(
            repository_id: query.repository_id,
            topic_id: query.decision_topic_id,
            policy_status: query.decision_policy_status,
            after_decision_id: query.after_decision_id,
            limit: query.first
          )
        ),
        guidance: guidance_page(query),
        choices: choice_page(query),
        impacts: impact_page(
          relation: impacts_for_repository(query.repository_id),
          outcome: query.impact_outcome,
          after_global_position: query.after_impact_global_position,
          after_assessment_id: query.after_impact_assessment_id,
          limit: query.first
        )
      )
    end

    def decision(query)
      project = find_project(query.repository_id)
      membership = Coordinator::Read::DecisionRepositoryMembership.find_by(
        repository_id: query.repository_id,
        decision_id: query.decision_id
      )
      return unless project && membership

      decision = @decisions.fetch(query.decision_id)
      decision && Coordinator::Read::Web::GovernanceBrowserV1::DecisionDetail.new(
        project: build_project(project),
        decision:,
        membership_bases: membership.membership_bases
      )
    end

    def guidance(query)
      project = find_project(query.repository_id)
      record = guidance_for_repository(query.repository_id).find_by(message_id: query.message_id)
      return unless project && record

      page = @interpretations.page(
        Coordinator::Read::InterpretationListQueryV1.new(
          message_id: query.message_id,
          after_revision: query.after_revision,
          limit: query.first
        )
      )
      Coordinator::Read::Web::GovernanceBrowserV1::GuidanceDetail.new(
        project: build_project(project),
        guidance: @utterances.fetch(query.message_id),
        interpretations: Coordinator::Read::InterpretationPageV1.new(
          message_id: query.message_id,
          interpretations: page.records,
          next_after_revision: page.next_after_revision
        )
      )
    end

    def choice(query)
      project = find_project(query.repository_id)
      record = choices_for_repository(query.repository_id).find_by(choice_id: query.choice_id)
      return unless project && record

      Coordinator::Read::Web::GovernanceBrowserV1::ChoiceDetail.new(
        project: build_project(project),
        choice: @choices.fetch(query.choice_id),
        impacts: impact_page(
          relation: impacts_for_repository(query.repository_id).where(choice_id: query.choice_id),
          outcome: nil,
          after_global_position: query.after_impact_global_position,
          after_assessment_id: query.after_impact_assessment_id,
          limit: query.first
        )
      )
    end

    def receipts(query)
      relation = Coordinator::Read::CommandReceipt.all
      relation = relation.where(tool_name: query.tool_name) if query.tool_name
      relation = relation.where(status: query.status) if query.status
      relation = relation.where("command_id > ?", query.after_command_id) if query.after_command_id
      rows = relation.order(:command_id).limit(query.first + 1).to_a
      has_more = rows.length > query.first
      page_rows = rows.first(query.first)

      Coordinator::Read::Web::GovernanceBrowserV1::ReceiptPage.new(
        items: page_rows.map { build_receipt(_1) },
        next_command_id: has_more ? page_rows.last.command_id : nil,
        has_more:
      )
    end

    def receipt(query)
      record = Coordinator::Read::CommandReceipt.find_by(command_id: query.command_id)
      record && Coordinator::Read::Web::GovernanceBrowserV1::ReceiptDetail.new(
        receipt: build_receipt(record)
      )
    end

    private

    def find_project(repository_id)
      Coordinator::Read::Repository.find_by(repository_id:)
    end

    def build_project(record)
      Coordinator::Read::Web::GovernanceBrowserV1::Project.new(
        repository_id: record.repository_id,
        scope: record.scope,
        display_name: record.display_name
      )
    end

    def guidance_page(query)
      relation = guidance_for_repository(query.repository_id)
      relation = relation.where(source: query.guidance_source) if query.guidance_source
      if query.after_guidance_message_id
        relation = relation.where("message_id > ?", query.after_guidance_message_id)
      end
      ids = relation.order(:message_id).limit(query.first + 1).pluck(:message_id)
      has_more = ids.length > query.first
      page_ids = ids.first(query.first)

      Coordinator::Read::Web::GovernanceBrowserV1::GuidancePage.new(
        items: @utterances.fetch_many(page_ids),
        next_message_id: has_more ? page_ids.last : nil,
        has_more:
      )
    end

    def choice_page(query)
      relation = choices_for_repository(query.repository_id)
      relation = relation.where(choice_type: query.choice_type) if query.choice_type
      relation = relation.where(observation_status: query.choice_status) if query.choice_status
      relation = relation.where("choice_id > ?", query.after_choice_id) if query.after_choice_id
      ids = relation.order(:choice_id).limit(query.first + 1).pluck(:choice_id)
      has_more = ids.length > query.first
      page_ids = ids.first(query.first)

      Coordinator::Read::Web::GovernanceBrowserV1::AgentChoicePage.new(
        items: @choices.fetch_many(page_ids),
        next_choice_id: has_more ? page_ids.last : nil,
        has_more:
      )
    end

    def impact_page(relation:, outcome:, after_global_position:, after_assessment_id:, limit:)
      relation = relation.where(outcome:) if outcome
      if after_global_position && after_assessment_id
        relation = relation.where(
          "event_global_position > ? OR " \
          "(event_global_position = ? AND assessment_id > ?)",
          after_global_position,
          after_global_position,
          after_assessment_id
        )
      end
      rows = relation.order(:event_global_position, :assessment_id).limit(limit + 1).to_a
      has_more = rows.length > limit
      page_rows = rows.first(limit)
      last = page_rows.last

      Coordinator::Read::Web::GovernanceBrowserV1::ImpactPage.new(
        items: @impacts.fetch_many(page_rows.map(&:assessment_id)),
        next_cursor: has_more ? Coordinator::Read::Web::GovernanceBrowserV1::ImpactCursor.new(
          global_position: last.event_global_position,
          assessment_id: last.assessment_id
        ) : nil,
        has_more:
      )
    end

    def guidance_for_repository(repository_id)
      Coordinator::Read::UserUtterance.where(
        <<~SQL.squish,
          COALESCE(anchors -> 'repository_ids', '[]'::jsonb) @> ?::jsonb
          OR anchors ->> 'change_set_id' IN (
            SELECT change_set_id
            FROM coordination_dashboard_work_items
            WHERE repository_id = ?
          )
          OR anchors ->> 'work_item_id' IN (
            SELECT work_item_id
            FROM coordination_dashboard_work_items
            WHERE repository_id = ?
          )
          OR anchors ->> 'attempt_id' IN (
            SELECT attempt.attempt_id
            FROM attempt_histories AS attempt
            JOIN coordination_dashboard_work_items AS work_item
              ON work_item.change_set_id = attempt.change_set_id
             AND work_item.work_item_id = attempt.work_item_id
            WHERE work_item.repository_id = ?
          )
        SQL
        JSON.generate([ repository_id ]),
        repository_id,
        repository_id,
        repository_id
      )
    end

    def choices_for_repository(repository_id)
      Coordinator::Read::AgentChoice.where("context ->> 'repository_id' = ?", repository_id)
    end

    def impacts_for_repository(repository_id)
      Coordinator::Read::AgentChoiceImpact.where(
        attempt_id: attempts_for_repository(repository_id).select(:attempt_id)
      )
    end

    def attempts_for_repository(repository_id)
      Coordinator::Read::AttemptHistory.joins(
        <<~SQL.squish
          INNER JOIN coordination_dashboard_work_items AS governance_work_item
            ON governance_work_item.change_set_id = attempt_histories.change_set_id
           AND governance_work_item.work_item_id = attempt_histories.work_item_id
        SQL
      ).where("governance_work_item.repository_id = ?", repository_id)
    end

    def build_receipt(record)
      completion = record.completion
      Coordinator::Read::Web::GovernanceBrowserV1::CommandReceipt.new(
        command_id: record.command_id,
        tool_name: record.tool_name,
        status: record.status,
        summary: record.summary,
        receipt: record.receipt,
        warnings: completion.fetch("warnings"),
        next_action_tools: completion.fetch("next_actions").map { _1.fetch("tool") },
        emitted_events: completion.fetch("emitted_events").map { build_event_reference(_1) },
        completed_at: completion.fetch("completed_at")
      )
    end

    def build_event_reference(attributes)
      Coordinator::Read::Web::GovernanceBrowserV1::EventReference.new(
        event_id: attributes.fetch("event_id"),
        type: attributes.fetch("type"),
        stream_context: attributes.fetch("stream_context"),
        stream_name: attributes.fetch("stream_name"),
        stream_id: attributes.fetch("stream_id"),
        stream_revision: attributes.fetch("stream_revision")
      )
    end
  end
end
