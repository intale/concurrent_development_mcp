# frozen_string_literal: true

module Coordinator::Read::Projections
  class Repositories
    def initialize(patches:, paths: {}, remotes: {})
      @patches, @paths, @remotes = patches, paths, remotes
    end

    def apply(event)
      data = event.data
      identity = { repository_id: data.fetch("repository_id") }
      case event.type
      when "RepositoryRegistered"
        attributes = identity.merge(scope: data.fetch("scope"), **Source.evidence(event, prefix: :registered))
        @patches.insert(attributes.merge(display_name: nil, paths: [], remotes: [], created_at: event.created_at, updated_at: event.created_at))
        @patches.assign(attributes)
      when "RepositoryDisplayNameChanged"
        @patches.assign(identity.merge(display_name: data.fetch("display_name")))
      when "RepositoryPathAdded", "RepositoryPathRemoved"
        change_membership(@paths, identity, :paths, data.fetch("path"), added: event.type == "RepositoryPathAdded")
      when "RepositoryRemoteAdded", "RepositoryRemoteRemoved"
        change_membership(@remotes, identity, :remotes, data.fetch("remote"), added: event.type == "RepositoryRemoteAdded")
      end
      @patches.touch(identity, time: event.created_at)
      nil
    end

    private

    def change_membership(collections, identity, column, value, added:)
      key = identity.fetch(:repository_id)
      current = collections.fetch(key, [])
      collections[key] = added ? (current + [ value ]).uniq : current - [ value ]
      @patches.assign(identity.merge(column => collections.fetch(key)))
      nil
    end
  end
end
