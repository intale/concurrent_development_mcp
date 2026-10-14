# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class Assembler
      PRESENTERS = [ Coordination, Catalog, WorkIntentions, Decisions, Verification, Integration, OperationBatches ].freeze

      def initialize(facts:)
        @facts = facts
        @presenters = [ Coordination.new, Catalog.new(facts:), WorkIntentions.new(facts:), Decisions.new(facts:),
          Verification.new, Integration.new(facts:), OperationBatches.new(facts:) ].flat_map do |presenter|
          presenter.class::TOOLS.map { [ _1, presenter ] }
        end.to_h
      end

      def call(source)
        presentation = case source.terminal_event.type
        when "CommandRejected" then rejection(source, source.data(source.terminal_event).fetch(:error))
        when "CommandExecutionFailed" then failure(source)
        else
          result = @presenters.fetch(source.tool_name).call(source)
          data = result.fetch(:data)
          if OperationBatches::TOOLS.include?(source.tool_name) && source.tool_name != "operation_batch_cancel" &&
             (data.fetch(:status) == "cancelled" || data.fetch(:rejected).positive? || data.fetch(:failed).positive?)
            code = data.fetch(:status) == "cancelled" ? "operation_batch_cancelled" : "operation_batch_partial_failure"
            rejection(source, { code:, message: result.fetch(:summary), details: data }, next_actions: result.fetch(:next_actions))
          else
            result.merge(status: "ok", receipt: source.request_id)
          end
        end
        presentation.merge(
          command_id: source.request_id, tool_name: source.tool_name, canonical_input_digest: source.canonical_input_digest,
          emitted_events: source.persisted_events.map { source.reference(_1) }, completed_at: source.completed_at
        )
      end

      private

      def rejection(source, error, next_actions: nil)
        source.presentation(error.fetch(:message), error, next_actions: next_actions || rejection_actions(error))
          .merge(status: Coordinator::Write::Tasks::ToolResultMapper::STATUS_BY_CODE.fetch(error.fetch(:code).to_sym), receipt: nil)
      end

      def rejection_actions(error)
        details = error.fetch(:details)
        case error.fetch(:code)
        when "skill_revision_conflict"
          [ { tool: "skill_get", arguments: details.slice(:name, :scope) } ]
        when "stale_decision_context"
          [ { tool: "decision_resolve", arguments: details.slice(:topic_id, :context) } ]
        else []
        end
      end

      def failure(source)
        fact = source.data(source.terminal_event)
        details = fact.except(:command_id)
        if source.tool_name == "work_intention_set_renew"
          events = @facts.history(:work_intention_set_renewal, source.command_id,
            %w[WorkIntentionRenewalAssigned WorkIntentionRenewalCompleted WorkIntentionRenewalFailed], maximum_count: 64)
            .select { _1.global_position <= source.terminal_event.global_position }
          failed = events.find { _1.type == "WorkIntentionRenewalFailed" }
          if failed
            completed = events.select { _1.type == "WorkIntentionRenewalCompleted" }.map { _1.data.fetch("intention_id") }
            failed_id = failed.data.fetch("intention_id")
            pending = events.select { _1.type == "WorkIntentionRenewalAssigned" }.map { _1.data.fetch("intention_id") } - completed - [ failed_id ]
            details = details.merge(renewal_id: source.command_id, completed_intention_ids: completed,
              failed_intention_id: failed_id, pending_intention_ids: pending)
          end
        end
        rejection(source, { code: "saga_execution_failed", message: fact.fetch(:reason), details: })
      end
    end
  end
end
