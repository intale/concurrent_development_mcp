# frozen_string_literal: true

module Coordinator::Read::Projections
  class CoordContexts
    VERSION = 7
    WORK_ITEM_LIMIT = 100
    DEPENDENCY_LIMIT = 500
    ATTEMPT_LIMIT = 100

    def self.initial
      { schema: "coord-context/v1", change_set: nil, work_item_ids: [], work_items: [], dependencies: [], attempts: [], candidate_checkpoints: [] }
    end

    def initialize(contexts:, histories:, scopes:, documents: {}, positions: {}, checkpoint_numbers: {}, history_documents: {})
      @contexts, @histories, @scopes = contexts, histories, scopes
      @documents, @positions, @checkpoint_numbers, @history_documents = documents, positions, checkpoint_numbers, history_documents
    end

    def apply(event, source:)
      id = source.fetch(:change_set_id)
      state = (@documents[id] ||= self.class.initial)
      time = event.created_at.utc.iso8601(6)
      case event.type
      when "ChangeSetAcceptanceCriteriaDefined"
        state[:change_set] = { status: "planning", activated_at: nil, completed_at: nil }.merge(state[:change_set] || {}).merge(source)
      when "ChangeSetActivated" then state.fetch(:change_set).merge!(status: "active", activated_at: time)
      when "ChangeSetCompleted" then state.fetch(:change_set).merge!(status: "completed", completed_at: time)
      when "WorkItemCompetitiveModeSelected"
        member(state, :work_items, :work_item_id, source, defaults: work_item_defaults)
        state[:work_item_ids] |= [ source.fetch(:work_item_id) ]
      when "WorkItemMadeReady"
        work_item(state, source, status: "ready", made_ready_at: time)
      when "WorkItemAcquired"
        work_item(state, source, status: "acquired", active_attempt_id: source.fetch(:attempt_id), active_agent_id: source.fetch(:agent_id), acquired_at: time)
      when "WorkItemRequeued"
        work_item(state, source, status: "ready", active_attempt_id: nil, active_agent_id: nil, made_ready_at: time, acquired_at: nil)
      when "WorkItemCandidateSelected"
        work_item(state, source, selected_candidate_id: source.fetch(:candidate_id), selected_candidate_event: source.fetch(:candidate_event), selected_at: time)
      when "WorkItemCompleted"
        work_item(state, source, status: "completed", selected_candidate_id: source.fetch(:candidate_id), selected_candidate_event: source.fetch(:candidate_event),
          produced_outputs: source.fetch(:produced_outputs), completed_at: time)
      when "WorkItemDependencyDeclared"
        member(state, :dependencies, :dependency_id, source.except(:change_set_id), defaults: { source_event: nil, declared_at: time, satisfied_at: nil })
      when "WorkItemDependencySatisfied"
        member(state, :dependencies, :dependency_id, source.except(:change_set_id, :source).merge(source_event: source.fetch(:source), satisfied_at: time))
      when "AttemptStarted" then attempt_started(state, source, event)
      when "AttemptAbandoned", "AttemptCompleted" then attempt_terminal(state, source, event)
      when "CandidateSubmitted" then member(state, :candidate_checkpoints, :attempt_id, source)
      when "ResourceWorkIntentionDeclared", "ResourceWorkIntentionRenewed", "ResourceWorkIntentionWithdrawn", "ResourceWorkIntentionExpired"
        intention(state, source, event)
      when "ChangeSetRepositoryCheckpointNumberChanged"
        numbers = (@checkpoint_numbers[id] ||= {})
        numbers[source.fetch(:repository_id).to_sym] = source.fetch(:checkpoints_number)
        @contexts.assign(change_set_id: id, repository_checkpoint_numbers: numbers)
      end
      retain(state)
      persist_context(id, state, event)
      roots(source, event)
      nil
    end

    private

    def work_item_defaults
      { status: "planned", active_attempt_id: nil, active_agent_id: nil, selected_candidate_id: nil, selected_candidate_event: nil,
        produced_outputs: [], made_ready_at: nil, acquired_at: nil, selected_at: nil, completed_at: nil }
    end

    def work_item(state, source, **changes)
      existing(state, :work_items, :work_item_id, source.fetch(:work_item_id), **changes)
    end

    def member(state, collection, key, changes, defaults: {})
      rows = state.fetch(collection)
      index = rows.index { _1.fetch(key) == changes.fetch(key) }
      if index
        rows[index] = rows.fetch(index).merge(changes)
      else
        rows << defaults.merge(changes)
      end
      nil
    end

    def existing(state, collection, key, id, **changes)
      row = state.fetch(collection).find { _1.fetch(key) == id }
      row&.merge!(changes)
      nil
    end

    def attempt_started(state, source, event)
      document = source.except(:authorization_event, :authorized_global_position).merge(status: "started")
      defaults = { work_intention_set: nil, selected_candidate_id: nil, selected_candidate_event: nil, completed_at: nil,
        abandonment_reason: nil, abandoned_at: nil }
      member(state, :attempts, :attempt_id, document, defaults:)
      attributes = source.slice(:attempt_id, :change_set_id, :work_item_id, :agent_id, :base_snapshots, :authorization_event).merge(
        status: "started", authorized_global_position: source.fetch(:authorized_global_position),
        authorized_at_domain: source.fetch(:authorized_at), started_at_domain: source.fetch(:started_at), projection_version: VERSION)
      @histories.insert(attributes.merge(created_at: Time.iso8601(source.fetch(:authorized_at)), updated_at: event.created_at))
      @histories.assign(attributes)
      @histories.touch(source.slice(:attempt_id), time: event.created_at)
    end

    def attempt_terminal(state, source, event)
      time = event.created_at.utc.iso8601(6)
      completed = event.type == "AttemptCompleted"
      changes = completed ? { status: "completed", work_intention_set: nil, selected_candidate_id: source.fetch(:candidate_id),
        selected_candidate_event: source.fetch(:candidate_event), completed_at: time } :
        { status: "abandoned", work_intention_set: nil, abandonment_reason: source.fetch(:reason), abandoned_at: time }
      existing(state, :attempts, :attempt_id, source.fetch(:attempt_id), **changes)
      attributes = { attempt_id: source.fetch(:attempt_id), status: changes.fetch(:status), terminal_event: Source.reference(event), terminal_at_domain: event.created_at }
      attributes.merge!(changes.slice(:selected_candidate_id, :selected_candidate_event, :abandonment_reason))
      @histories.assign(attributes)
      @histories.touch(source.slice(:attempt_id), time: event.created_at)
    end

    def intention(state, source, event)
      id = source.fetch(:attempt_id)
      history = (@history_documents[id] ||= {})
      current_id = history[:work_intention_set_id]
      replacement = current_id != source.fetch(:set_id)
      if replacement
        history.merge!(work_intention_set_last_expanded_event: nil, work_intention_set_last_renewed_event: nil, work_intention_set_withdrawal_event: nil)
      end
      current_set = current_id == source.fetch(:set_id) ? set_from_history(history) : initial_set(source)
      tracking = current_id == source.fetch(:set_id) ? (history[:work_intention_member_states] || {}) : {}
      member_id = source.fetch(:member).fetch(:intention_id)
      member_state = (tracking[member_id.to_sym] ||= { expires_at: source.fetch(:declared_expires_at), withdrawn_at: nil })
      time = event.created_at.utc.iso8601(6)
      case event.type
      when "ResourceWorkIntentionDeclared"
        current_set[:intentions] = upsert_intention(current_set.fetch(:intentions), source.fetch(:member))
        if source.fetch(:expanded)
          current_set.merge!(last_expanded_at: time)
          history[:work_intention_set_last_expanded_event] = Source.reference(event)
        end
      when "ResourceWorkIntentionRenewed"
        member_state[:expires_at] = source.fetch(:expires_at)
        current_set.merge!(last_renewed_at: time, previous_expires_at: source.fetch(:previous_expires_at))
        history[:work_intention_set_last_renewed_event] = Source.reference(event)
      when "ResourceWorkIntentionWithdrawn", "ResourceWorkIntentionExpired"
        member_state.merge!(withdrawn_at: time, withdrawal_event: Source.reference(event), withdrawal_position: event.global_position)
      end
      references = current_set.fetch(:intentions)
      known = references.filter_map { tracking[_1.fetch(:intention_id).to_sym] }
      if known.length == references.length && known.any?
        current_set[:expires_at] = known.map { _1.fetch(:expires_at) }.min
        if known.all? { _1[:withdrawn_at] }
          last = known.max_by { _1.fetch(:withdrawal_position) }
          current_set[:withdrawn_at] = last.fetch(:withdrawn_at)
          history[:work_intention_set_withdrawal_event] = last.fetch(:withdrawal_event)
        end
      end
      attributes = history_attributes(source, current_set, history, tracking)
      history.merge!(attributes)
      columns = if replacement
        attributes.keys
      else
        case event.type
        when "ResourceWorkIntentionDeclared"
          %i[attempt_id work_intention_member_states work_intention_set_intentions work_intention_set_expires_at_domain
            work_intention_set_last_expanded_event work_intention_set_last_expanded_at_domain]
        when "ResourceWorkIntentionRenewed"
          %i[attempt_id work_intention_member_states work_intention_set_last_renewed_event work_intention_set_last_renewed_at_domain
            work_intention_set_previous_expires_at_domain work_intention_set_expires_at_domain]
        else
          %i[attempt_id work_intention_member_states work_intention_set_withdrawal_event work_intention_set_withdrawn_at_domain]
        end
      end
      @histories.assign(attributes.slice(*columns))
      @histories.touch({ attempt_id: id }, time: event.created_at)
      existing(state, :attempts, :attempt_id, id, work_intention_set: current_set)
      nil
    end

    def upsert_intention(references, member)
      index = references.index { _1.fetch(:intention_id) == member.fetch(:intention_id) }
      values = references.dup
      index ? values[index] = values.fetch(index).merge(member) : values << member
      values.sort_by { _1.fetch(:resource_id).b }
    end

    def initial_set(source)
      { intention_set_id: source.fetch(:set_id), repository_id: source.fetch(:repository_id), policy_version: source.fetch(:policy_version),
        intentions: [], declared_at: source.fetch(:declared_at), last_expanded_at: nil, last_renewed_at: nil, previous_expires_at: nil,
        expires_at: source.fetch(:declared_expires_at), withdrawn_at: nil }
    end

    def set_from_history(history)
      { intention_set_id: history.fetch(:work_intention_set_id), repository_id: history.fetch(:work_intention_set_repository_id),
        policy_version: history.fetch(:work_intention_set_policy_version), intentions: history.fetch(:work_intention_set_intentions),
        declared_at: history.fetch(:work_intention_set_declared_at_domain), last_expanded_at: history[:work_intention_set_last_expanded_at_domain],
        last_renewed_at: history[:work_intention_set_last_renewed_at_domain], previous_expires_at: history[:work_intention_set_previous_expires_at_domain],
        expires_at: history.fetch(:work_intention_set_expires_at_domain), withdrawn_at: history[:work_intention_set_withdrawn_at_domain] }
    end

    def history_attributes(source, set, history, tracking)
      { attempt_id: source.fetch(:attempt_id), work_intention_set_id: set.fetch(:intention_set_id),
        work_intention_set_repository_id: set.fetch(:repository_id), work_intention_set_policy_version: set.fetch(:policy_version),
        work_intention_set_intentions: set.fetch(:intentions), work_intention_set_declared_event: source.fetch(:created_event),
        work_intention_set_declared_at_domain: set.fetch(:declared_at), work_intention_set_last_expanded_event: history[:work_intention_set_last_expanded_event],
        work_intention_set_last_expanded_at_domain: set[:last_expanded_at], work_intention_set_last_renewed_event: history[:work_intention_set_last_renewed_event],
        work_intention_set_last_renewed_at_domain: set[:last_renewed_at], work_intention_set_previous_expires_at_domain: set[:previous_expires_at],
        work_intention_set_expires_at_domain: set.fetch(:expires_at), work_intention_set_withdrawal_event: history[:work_intention_set_withdrawal_event],
        work_intention_set_withdrawn_at_domain: set[:withdrawn_at], work_intention_member_states: tracking }
    end

    def retain(state)
      state[:work_items] = state.fetch(:work_items).last(WORK_ITEM_LIMIT)
      state[:dependencies] = state.fetch(:dependencies).last(DEPENDENCY_LIMIT)
      active, terminal = state.fetch(:attempts).partition { !%w[abandoned completed].include?(_1.fetch(:status)) }
      active = active.sort_by { [ _1.fetch(:authorized_at), _1.fetch(:attempt_id).b ] }.last(ATTEMPT_LIMIT)
      capacity = ATTEMPT_LIMIT - active.length
      historical = capacity.positive? ? terminal.sort_by { [ _1.fetch(:authorized_at), _1.fetch(:attempt_id).b ] }.last(capacity) : []
      state[:attempts] = (active + historical).sort_by { [ _1.fetch(:authorized_at), _1.fetch(:attempt_id).b ] }.reverse
      ids = state.fetch(:attempts).map { _1.fetch(:attempt_id) }
      state[:candidate_checkpoints] = state.fetch(:candidate_checkpoints).select { ids.include?(_1.fetch(:attempt_id)) }
    end

    def persist_context(id, state, event)
      positions = (@positions[id] ||= [])
      key = [ event.stream.context, event.stream.stream_name, event.stream.stream_id ]
      positions.reject! { _1.values_at(:stream_context, :stream_name, :stream_id) == key }
      positions << { stream_context: key[0], stream_name: key[1], stream_id: key[2], stream_revision: event.stream_revision }
      retained = retained_streams(state).to_set
      positions.select! { retained.include?(_1.values_at(:stream_context, :stream_name, :stream_id)) }
      positions.sort_by! { _1.values_at(:stream_context, :stream_name, :stream_id) }
      attributes = { change_set_id: id, projection_version: VERSION, document: state, source_positions: positions, last_processed_at: event.created_at }
      @contexts.insert(attributes.merge(repository_checkpoint_numbers: @checkpoint_numbers.fetch(id, {}), created_at: event.created_at, updated_at: event.created_at))
      @contexts.assign(attributes)
      @contexts.touch({ change_set_id: id }, time: event.created_at)
    end

    def retained_streams(state)
      streams = []
      streams << [ "DevelopmentPlanning", "ChangeSet", state.fetch(:change_set).fetch(:change_set_id) ] if state[:change_set]
      state.fetch(:work_items).each { streams << [ "DevelopmentExecution", "WorkItem", _1.fetch(:work_item_id) ] }
      state.fetch(:attempts).each do |attempt|
        streams << [ "DevelopmentExecution", "Attempt", attempt.fetch(:attempt_id) ]
        attempt[:work_intention_set]&.fetch(:intentions)&.each { streams << [ "DevelopmentCoordination", "ResourceWorkIntention", _1.fetch(:intention_id) ] }
      end
      state.fetch(:candidate_checkpoints).each { streams << [ "DevelopmentIntegration", "Candidate", _1.fetch(:candidate_id) ] }
      streams
    end

    def roots(source, event)
      id = source.fetch(:change_set_id)
      { change_set: id, work_item: source[:work_item_id], attempt: source[:attempt_id] }.each do |kind, root|
        next unless root

        attributes = { scope_kind: kind.to_s, scope_id: root, change_set_id: id }
        @scopes.insert(attributes.merge(created_at: event.created_at, updated_at: event.created_at))
        @scopes.assign(attributes)
        @scopes.touch(attributes.slice(:scope_kind, :scope_id), time: event.created_at)
      end
      nil
    end
  end
end
