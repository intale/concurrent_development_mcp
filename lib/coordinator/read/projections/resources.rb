# frozen_string_literal: true

module Coordinator::Read::Projections
  class Resources
    def initialize(patches:)
      @patches = patches
    end

    def apply(event)
      data = event.data
      identity = { resource_id: data.fetch("resource_id") }
      @patches.insert(identity.merge(repository_id: data.fetch("repository_id"), kind: data.fetch("kind"),
        normalized_path: data.fetch("normalized_path"), lifecycle_status: "registered",
        created_at: event.created_at, updated_at: event.created_at))
      case event.type
      when "ResourceRegistered"
        @patches.assign(identity.merge(Source.evidence(event, prefix: :registered)))
      when "ResourceBound"
        @patches.assign(identity.merge(Source.evidence(event, prefix: :latest_transition))
          .merge(lifecycle_status: "current", unbinding_reason: nil))
      when "ResourceUnbound"
        @patches.assign(identity.merge(Source.evidence(event, prefix: :latest_transition))
          .merge(lifecycle_status: "inactive", unbinding_reason: data.fetch("reason")))
      end
      @patches.touch(identity, time: event.created_at)
      nil
    end
  end
end
