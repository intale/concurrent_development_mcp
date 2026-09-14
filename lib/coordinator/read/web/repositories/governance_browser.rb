# frozen_string_literal: true

module Coordinator::Read::Web::Repositories
  class GovernanceBrowser
    include EventTimePagination

    def initialize(
      decisions: Coordinator::Read::Repositories::DecisionGovernance.new,
      utterances: Coordinator::Read::Repositories::UserUtterances.new,
      interpretations: Coordinator::Read::Repositories::DecisionInterpretations.new,
      choices: Coordinator::Read::Repositories::AgentChoices.new,
      impacts: Coordinator::Read::Repositories::AgentChoiceImpacts.new,
      completion_contract: Coordinator::Read::Web::Contracts::GovernanceBrowser::CommandCompletion.new
    )
      @decisions = decisions
      @utterances = utterances
      @interpretations = interpretations
      @choices = choices
      @impacts = impacts
      @completion_contract = completion_contract
    end

    def decisions(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      relation = decisions_for_project(repository_ids)
      if query.topic_id
        relation = relation.where("definition #>> '{document,topic,topic_id}' = ?", query.topic_id)
      end
      relation = relation.where(policy_status: query.policy_status) if query.policy_status
      rows, has_more = event_time_page(
        relation:,
        id_column: :decision_id,
        after_updated_at: query.after_updated_at,
        after_id: query.after_decision_id,
        limit: query.first,
        sort: query.sort
      )
      page_ids = rows.map(&:decision_id)

      Coordinator::Read::Web::GovernanceBrowserV1::DecisionPage.new(
        items: @decisions.fetch_many(page_ids),
        next_decision_id: has_more ? page_ids.last : nil,
        next_updated_at: has_more ? event_time(rows.last) : nil,
        has_more:
      )
    end

    def guidance_list(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      relation = guidance_for_project(repository_ids)
      relation = relation.where(source: query.source) if query.source
      rows, has_more = event_time_page(
        relation:,
        id_column: :message_id,
        after_updated_at: query.after_updated_at,
        after_id: query.after_message_id,
        limit: query.first,
        sort: query.sort
      )
      page_ids = rows.map(&:message_id)

      Coordinator::Read::Web::GovernanceBrowserV1::GuidancePage.new(
        items: @utterances.fetch_many(page_ids),
        next_message_id: has_more ? page_ids.last : nil,
        next_updated_at: has_more ? event_time(rows.last) : nil,
        has_more:
      )
    end

    def choices(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      relation = choices_for_project(repository_ids)
      relation = relation.where(choice_type: query.choice_type) if query.choice_type
      relation = relation.where(observation_status: query.status) if query.status
      rows, has_more = event_time_page(
        relation:,
        id_column: :choice_id,
        after_updated_at: query.after_updated_at,
        after_id: query.after_choice_id,
        limit: query.first,
        sort: query.sort
      )
      page_ids = rows.map(&:choice_id)

      Coordinator::Read::Web::GovernanceBrowserV1::AgentChoicePage.new(
        items: @choices.fetch_many(page_ids),
        next_choice_id: has_more ? page_ids.last : nil,
        next_updated_at: has_more ? event_time(rows.last) : nil,
        has_more:
      )
    end

    def impacts(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      impact_page(
        relation: impacts_for_project(repository_ids),
        outcome: query.outcome,
        after_updated_at: query.after_updated_at,
        after_assessment_id: query.after_assessment_id,
        limit: query.first,
        sort: query.sort
      )
    end

    def decision(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      memberships = Coordinator::Read::DecisionRepositoryMembership.where(
        repository_id: repository_ids,
        decision_id: query.decision_id
      ).to_a
      return if memberships.empty?

      decision = @decisions.fetch(query.decision_id)
      decision && Coordinator::Read::Web::GovernanceBrowserV1::DecisionDetail.new(
        decision:,
        membership_bases: memberships.flat_map(&:membership_bases).uniq.sort
      )
    end

    def guidance(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      record = guidance_for_project(repository_ids).find_by(message_id: query.message_id)
      return unless record

      page = @interpretations.page(
        Coordinator::Read::InterpretationListQueryV1.new(
          message_id: query.message_id,
          after_revision: query.after_revision,
          limit: query.first
        )
      )
      Coordinator::Read::Web::GovernanceBrowserV1::GuidanceDetail.new(
        guidance: @utterances.fetch(query.message_id),
        interpretations: Coordinator::Read::InterpretationPageV1.new(
          message_id: query.message_id,
          interpretations: page.records,
          next_after_revision: page.next_after_revision
        )
      )
    end

    def choice(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      record = choices_for_project(repository_ids).find_by(choice_id: query.choice_id)
      return unless record

      Coordinator::Read::Web::GovernanceBrowserV1::ChoiceDetail.new(
        choice: @choices.fetch(query.choice_id),
        impacts: impact_page(
          relation: impacts_for_project(repository_ids).where(choice_id: query.choice_id),
          outcome: nil,
          after_updated_at: query.after_impact_updated_at,
          after_assessment_id: query.after_impact_assessment_id,
          limit: query.first,
          sort: "newest_first"
        )
      )
    end

    def impact(query)
      repository_ids = project_repository_ids(query.project_scope)
      return unless repository_ids

      record = impacts_for_project(repository_ids).find_by(assessment_id: query.assessment_id)
      return unless record

      Coordinator::Read::Web::GovernanceBrowserV1::ImpactDetail.new(
        impact: @impacts.fetch(query.assessment_id)
      )
    end

    def receipts(query)
      relation = Coordinator::Read::CommandReceipt.all
      relation = relation.where(tool_name: query.tool_name) if query.tool_name
      relation = relation.where(status: query.status) if query.status
      page_rows, has_more = event_time_page(
        relation:,
        id_column: :command_id,
        after_updated_at: query.after_updated_at,
        after_id: query.after_command_id,
        limit: query.first,
        sort: query.sort
      )

      Coordinator::Read::Web::GovernanceBrowserV1::ReceiptPage.new(
        items: page_rows.map { build_receipt(_1) },
        next_command_id: has_more ? page_rows.last.command_id : nil,
        next_updated_at: has_more ? event_time(page_rows.last) : nil,
        has_more:
      )
    end

    def receipt(query)
      record = Coordinator::Read::CommandReceipt.find_by(request_id: query.command_id)
      record && Coordinator::Read::Web::GovernanceBrowserV1::ReceiptDetail.new(
        receipt: build_receipt(record)
      )
    end

    private

    def project_repository_ids(project_scope)
      ids = Coordinator::Read::Repository.where(scope: project_scope).order(:repository_id).pluck(:repository_id)
      ids unless ids.empty?
    end

    def decisions_for_project(repository_ids)
      decision_ids = Coordinator::Read::DecisionRepositoryMembership.where(repository_id: repository_ids)
        .select(:decision_id)
      Coordinator::Read::DecisionDefinition.where(decision_id: decision_ids)
    end

    def impact_page(relation:, outcome:, after_updated_at:, after_assessment_id:, limit:, sort:)
      relation = relation.where(outcome:) if outcome
      if after_updated_at && after_assessment_id
        comparator = sort == "oldest_first" ? ">" : "<"
        relation = relation.where(
          "updated_at #{comparator} ? OR (updated_at = ? AND assessment_id #{comparator} ?)",
          after_updated_at,
          after_updated_at,
          after_assessment_id
        )
      end
      direction = sort == "oldest_first" ? :asc : :desc
      rows = relation.order(updated_at: direction, assessment_id: direction).limit(limit + 1).to_a
      has_more = rows.length > limit
      page_rows = rows.first(limit)
      last = page_rows.last

      Coordinator::Read::Web::GovernanceBrowserV1::ImpactPage.new(
        items: @impacts.fetch_many(page_rows.map(&:assessment_id)),
        next_cursor: has_more ? Coordinator::Read::Web::GovernanceBrowserV1::ImpactCursor.new(
          updated_at: event_time(last),
          assessment_id: last.assessment_id
        ) : nil,
        has_more:
      )
    end

    def guidance_for_project(repository_ids)
      Coordinator::Read::UserUtterance.where(
        <<~SQL.squish,
          EXISTS (
            SELECT 1
            FROM jsonb_array_elements_text(
              COALESCE(anchors -> 'repository_ids', '[]'::jsonb)
            ) AS anchor_repository(value)
            WHERE anchor_repository.value IN (?)
          )
          OR anchors ->> 'change_set_id' IN (
            SELECT change_set_id
            FROM coordination_dashboard_work_items
            WHERE repository_id IN (?)
          )
          OR anchors ->> 'work_item_id' IN (
            SELECT work_item_id
            FROM coordination_dashboard_work_items
            WHERE repository_id IN (?)
          )
          OR anchors ->> 'attempt_id' IN (
            SELECT attempt.attempt_id
            FROM attempt_histories AS attempt
            JOIN coordination_dashboard_work_items AS work_item
              ON work_item.change_set_id = attempt.change_set_id
             AND work_item.work_item_id = attempt.work_item_id
            WHERE work_item.repository_id IN (?)
          )
        SQL
        repository_ids,
        repository_ids,
        repository_ids,
        repository_ids
      )
    end

    def choices_for_project(repository_ids)
      Coordinator::Read::AgentChoice.where("context ->> 'repository_id' IN (?)", repository_ids)
    end

    def impacts_for_project(repository_ids)
      Coordinator::Read::AgentChoiceImpact.where(
        attempt_id: attempts_for_project(repository_ids).select(:attempt_id)
      )
    end

    def attempts_for_project(repository_ids)
      Coordinator::Read::AttemptHistory.joins(
        <<~SQL.squish
          INNER JOIN coordination_dashboard_work_items AS governance_work_item
            ON governance_work_item.change_set_id = attempt_histories.change_set_id
           AND governance_work_item.work_item_id = attempt_histories.work_item_id
        SQL
      ).where("governance_work_item.repository_id IN (?)", repository_ids)
    end

    def build_receipt(record)
      completion = load_completion(record)
      verify_projection!(record, completion)
      Coordinator::Read::Web::GovernanceBrowserV1::CommandReceipt.new(
        command_id: completion.fetch(:command_id),
        tool_name: completion.fetch(:tool_name),
        status: completion.fetch(:status),
        summary: completion.fetch(:summary),
        receipt: completion.fetch(:receipt),
        warnings: completion.fetch(:warnings),
        next_action_tools: completion.fetch(:next_actions).map { _1.fetch(:tool) },
        emitted_events: completion.fetch(:emitted_events).map { build_event_reference(_1) },
        completed_at: completion.fetch(:completed_at)
      )
    rescue Coordinator::Read::Web::GovernanceBrowserReadError
      raise
    rescue Dry::Struct::Error => error
      raise Coordinator::Read::Web::GovernanceBrowserReadError.new(
        command_id: record.command_id,
        reason: "invalid_completion"
      ), cause: error
    end

    def load_completion(record)
      completion = @completion_contract.call(record.completion)
      return completion.to_h if completion.success?

      raise Coordinator::Read::Web::GovernanceBrowserReadError.new(
        command_id: record.command_id,
        reason: "invalid_completion"
      )
    end

    def verify_projection!(record, completion)
      projected = record.attributes.symbolize_keys.slice(
        :tool_name,
        :canonical_input_digest,
        :status,
        :summary,
        :receipt
      ).merge(command_id: record.request_id)
      canonical = completion.slice(
        :command_id,
        :tool_name,
        :canonical_input_digest,
        :status,
        :summary,
        :receipt
      )
      return if projected == canonical

      raise Coordinator::Read::Web::GovernanceBrowserReadError.new(
        command_id: record.command_id,
        reason: "projection_mismatch"
      )
    end

    def build_event_reference(attributes)
      Coordinator::Read::Web::GovernanceBrowserV1::EventReference.new(
        event_id: attributes.fetch(:event_id),
        type: attributes.fetch(:type),
        stream_context: attributes.fetch(:stream_context),
        stream_name: attributes.fetch(:stream_name),
        stream_id: attributes.fetch(:stream_id),
        stream_revision: attributes.fetch(:stream_revision)
      )
    end
  end
end
