# frozen_string_literal: true

module Coordinator::Read::Skills
  class PublicationLoader
    REVISION_TYPES = %w[SkillRevisionCreated SkillRevisionDescriptionDefined SkillRevisionInstructionsDefined SkillRevisionRepresentationRecorded SkillAssetAddedToRevision].freeze
    ASSET_TYPES = %w[SkillAssetCreated SkillAssetPathDefined SkillAssetContentDefined SkillAssetExecutabilityDefined].freeze

    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new)
      @event_store, @stream_factory = event_store, stream_factory
    end

    def call(event)
      data = event.data
      id, revision_id = data.fetch("skill_id"), data.fetch("skill_revision_id")
      registration = facts(@stream_factory.skill(id), [ "SkillRegistered" ], 1).fetch("SkillRegistered").first
      registered = registration.data
      revision = facts(@stream_factory.skill_revision(revision_id), REVISION_TYPES,
        4 + Coordinator::Shared::Types::SKILL_ASSET_MAXIMUM_COUNT)
      assets = revision.fetch("SkillAssetAddedToRevision", []).map { asset(_1.data.fetch("asset_id")) }
      { skill_id: id, skill_revision_id: revision_id, revision: data.fetch("revision"),
        name: registered.fetch("name"), scope: registered.fetch("scope"),
        description: revision.fetch("SkillRevisionDescriptionDefined").first.data.fetch("description"),
        instructions: revision.fetch("SkillRevisionInstructionsDefined").first.data.fetch("instructions"),
        asset_count: revision.fetch("SkillRevisionRepresentationRecorded").first.metadata.fetch("asset_count"),
        assets:, content_digest: event.metadata.fetch("content_digest"), registered_at: registration.created_at, published_event: event }
    end

    private

    def facts(stream, types, maximum)
      @event_store.read(stream, Coordinator::Write::EventReadCriteria.new(
        event_types: types, maximum_count: maximum, direction: :asc
      )).group_by(&:type)
    end

    def asset(id)
      events = facts(@stream_factory.skill_asset(id), ASSET_TYPES, 4)
      content = events.fetch("SkillAssetContentDefined").first
      metadata = content.metadata
      text = metadata.fetch("encoding") == "utf-8"
      { path: events.fetch("SkillAssetPathDefined").first.data.fetch("path"),
        executable: events.fetch("SkillAssetExecutabilityDefined").first.data.fetch("executable"),
        media_type: metadata.fetch("media_type"), content_encoding: metadata.fetch("encoding"),
        content_text: text ? content.data.fetch("content") : nil,
        content_base64: text ? nil : content.data.fetch("content"),
        content_sha256: metadata.fetch("content_sha256"), byte_size: metadata.fetch("byte_size") }
    end
  end
end
