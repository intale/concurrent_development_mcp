# frozen_string_literal: true

module Coordinator::Read::ReleaseSets
  # The immutable preparation is bounded and trusted, like the delivered facts.
  class PreparationLoader
    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new)
      @event_store, @stream_factory = event_store, stream_factory
    end

    def call(release_set_id, through_revision:)
      events = @event_store.read(@stream_factory.release_set(release_set_id), Coordinator::Write::EventReadCriteria.new(
        event_types: %w[ReleaseSetCreated ReleaseSetMemberAdded],
        maximum_count: Coordinator::Shared::Types::RELEASE_SET_MAXIMUM_MEMBERS + 1,
        direction: :asc, to_revision: through_revision
      ))
      created = events.find { _1.type == "ReleaseSetCreated" }
      members = events.select { _1.type == "ReleaseSetMemberAdded" }.map do |event|
        data = Coordinator::Read::CommandResults::Source.document(event.data)
        data.slice(:repository_id, :merge_snapshot_id, :ordered_candidate_ids, :authorization_event)
          .merge(position: data.fetch(:member_position))
      end
      { change_set_id: created.data.fetch("change_set_id"), ordered_members: members, created_at: created.created_at }
    end
  end
end
