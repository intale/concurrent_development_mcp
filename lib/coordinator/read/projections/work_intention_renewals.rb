# frozen_string_literal: true

module Coordinator::Read::Projections
  class WorkIntentionRenewals
    def initialize(patches:, members: {})
      @patches = patches
      @members = members.transform_values { _1.to_h { |member| [ member.fetch("intention_id"), member ] } }
    end

    def apply(event)
      data = event.data
      identity = { renewal_id: data.fetch("renewal_id") }
      @patches.insert(identity.merge(status: "requested", members: [], created_at: event.created_at, updated_at: event.created_at))
      case event.type
      when "WorkIntentionSetRenewalRequested"
        @patches.assign(identity.merge(intention_set_id: data.fetch("intention_set_id"), attempt_id: data.fetch("attempt_id"),
          task_id: event.metadata["task_id"], expires_at: data.fetch("expires_at"),
          actor_kind: event.metadata.fetch("actor_kind"), actor_id: event.metadata.fetch("actor_id"),
          correlation_id: event.correlation_id, request_event: Source.reference(event), status: "requested"))
      when "WorkIntentionRenewalAssigned"
        members = owner_members(identity)
        key = data.fetch("intention_id")
        member = members.fetch(key, { "status" => "pending", "renewal_event" => nil, "failure" => nil })
        members[key] = member.merge(data.slice("position", "intention_id", "resource_id", "fencing_token"))
        assign_members(identity)
      when "WorkIntentionRenewalCompleted"
        member_outcome(identity, data.fetch("intention_id"), "status" => "completed", "renewal_event" => data.fetch("renewal_event"), "failure" => nil)
      when "WorkIntentionRenewalFailed"
        failure = data.except("renewal_id", "intention_id")
        member_outcome(identity, data.fetch("intention_id"), "status" => "failed", "renewal_event" => nil, "failure" => failure)
        @patches.assign(identity.merge(failure:))
      when "WorkIntentionSetRenewalCompleted"
        @patches.assign(identity.merge(status: "completed", failure: nil, terminal_event: Source.reference(event)))
      when "WorkIntentionSetRenewalFailed"
        @patches.assign(identity.merge(status: "failed", terminal_event: Source.reference(event)))
      end
      @patches.touch(identity, time: event.created_at)
      nil
    end

    private

    def owner_members(identity)
      @members[identity.fetch(:renewal_id)] ||= {}
    end

    def member_outcome(identity, intention_id, changes)
      members = owner_members(identity)
      members[intention_id] = members.fetch(intention_id, { "intention_id" => intention_id }).merge(changes)
      assign_members(identity)
      @patches.assign(identity.merge(status: "running"))
      nil
    end

    def assign_members(identity)
      members = owner_members(identity).values.sort_by { _1.fetch("position", Float::INFINITY) }
      @patches.assign(identity.merge(members:))
    end
  end
end
