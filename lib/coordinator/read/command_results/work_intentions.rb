# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class WorkIntentions
      TOOLS = %w[work_intention_set_declare work_intention_set_expand work_intention_set_renew work_intention_set_withdraw attempt_abandon].freeze
      SET_TYPES = %w[WorkIntentionSetCreated WorkIntentionAddedToSet].freeze
      DEADLINE_TYPES = %w[ResourceWorkIntentionDeclared ResourceWorkIntentionRenewed].freeze

      def initialize(facts:)
        @facts = facts
      end

      def call(source)
        return abandonment(source) if source.tool_name == "attempt_abandon"

        created = source.event("WorkIntentionSetCreated")
        id = created ? created.data.fetch("set_id") : source.input.fetch(:intention_set_id)
        evidence = evidence(source, id)
        data = source.values(:change_set_id, :work_item_id, :attempt_id).merge(
          intention_set_id: id, repository_id: evidence.fetch(:repository_id), policy_version: "coordinator-work-intention/v1"
        )
        summary = case source.tool_name
        when "work_intention_set_declare"
          data.merge!(declared_at: evidence.fetch(:declared_at), expires_at: evidence.fetch(:expires_at), intentions: evidence.fetch(:intentions))
          "Resource work intentions declared."
        when "work_intention_set_expand"
          added = source.events("ResourceWorkIntentionDeclared").map { reference(source, _1) }
          data.merge!(expanded_at: source.persisted_events.first ? source.timestamp(source.persisted_events.first) : source.completed_at,
            expires_at: evidence.fetch(:expires_at), added_intentions: added, intention_count: evidence.fetch(:intentions).length)
          "Work-intention set expanded."
        when "work_intention_set_renew"
          data.merge!(intentions: evidence.fetch(:intentions), intention_count: evidence.fetch(:intentions).length,
            renewed_at: timestamp(source, "ResourceWorkIntentionRenewed", "WorkIntentionSetRenewalRequested"),
            previous_expires_at: evidence.fetch(:previous_expires_at), expires_at: evidence.fetch(:expires_at))
          "Work-intention set renewed."
        when "work_intention_set_withdraw"
          data.merge!(intentions: evidence.fetch(:intentions), intention_count: evidence.fetch(:intentions).length,
            previous_expires_at: evidence.fetch(:expires_at), withdrawn_at: timestamp(source, "ResourceWorkIntentionWithdrawn"))
          "Work-intention set withdrawn."
        end
        source.presentation(summary, data, next_actions: [ source.action("coord_context", **source.values(:change_set_id)) ])
      end

      def reference(source, declaration)
        fact = source.data(declaration)
        resource = @facts.first(:resource, fact.fetch(:resource_id), "ResourceRegistered")
        fact.slice(:intention_id, :resource_id, :base_blob_oid, :mode, :purpose, :context, :fencing_token)
          .merge(resource_kind: resource.data.fetch("kind"), resource_path: resource.data.fetch("normalized_path"))
      end

      private

      def evidence(source, id)
        events = set_history(source, id)
        created = events.find { _1.type == "WorkIntentionSetCreated" }
        before = (source.persisted_events.map(&:global_position).min || source.terminal_event.global_position + 1) - 1
        members = memberships(source, events).map do |membership|
          intention_id = membership.data.fetch("intention_id")
          declared = @facts.first(:resource_work_intention, intention_id, "ResourceWorkIntentionDeclared")
          current = deadline(intention_id, source.terminal_event.global_position)
          prior = current.global_position <= before ? current : deadline(intention_id, before)
          { reference: reference(source, declared), current: current.data.fetch("expires_at"), prior: prior&.data&.fetch("expires_at") }
        end
        previous = members.map { _1.fetch(:prior) }
        { repository_id: created.data.fetch("repository_id"), declared_at: source.timestamp(created),
          intentions: members.map { _1.fetch(:reference) }, expires_at: members.map { _1.fetch(:current) }.min,
          previous_expires_at: previous.all? ? previous.min : nil }
      end

      def set_history(source, id)
        latest = @facts.latest(context: "DevelopmentCoordination", stream: "WorkIntentionSet", types: SET_TYPES,
          marker: "work-intention-set:#{id}", through_position: source.terminal_event.global_position)
        @facts.history(:work_intention_set, id, SET_TYPES, maximum_count: Coordinator::Write::EventQueries::WORK_INTENTION_SET_STATE.maximum_count,
          to_revision: latest.stream_revision)
      end

      def memberships(source, events)
        positions = {}
        events.select { _1.type == "WorkIntentionAddedToSet" }.select do |event|
          command_id = event.metadata.fetch("command_id")
          position = positions.fetch(command_id) { positions[command_id] = @facts.first(:command, command_id, "CommandSucceeded")&.global_position }
          position && position <= source.terminal_event.global_position
        end
      end

      def deadline(id, position)
        return if position.negative?

        @facts.latest(context: "DevelopmentCoordination", stream: "ResourceWorkIntention", types: DEADLINE_TYPES,
          marker: "work-intention:#{id}", through_position: position)
      end

      def timestamp(source, type, fallback = nil)
        event = source.events(type).last || source.event(fallback) || source.terminal_event
        source.timestamp(event)
      end

      def abandonment(source)
        withdrawn = source.events("ResourceWorkIntentionWithdrawn").length
        created = @facts.indexed(context: "DevelopmentCoordination", stream: "WorkIntentionSet", types: [ "WorkIntentionSetCreated" ],
          marker: "attempt:#{source.input.fetch(:attempt_id)}", through_position: source.terminal_event.global_position)
        total = created ? memberships(source, set_history(source, created.stream.stream_id)).length : 0
        warnings = [ "Reacquire the WorkItem with a fresh Attempt ID and base snapshot before resuming." ]
        warnings << "#{total - withdrawn} work intention(s) were already inactive and were left unchanged." if total > withdrawn
        source.presentation("Attempt abandoned; WorkItem requeued; #{withdrawn} active work intention(s) withdrawn.",
          source.values(:change_set_id, :work_item_id, :attempt_id), warnings:)
      end
    end
  end
end
