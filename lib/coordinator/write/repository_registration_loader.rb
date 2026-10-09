# frozen_string_literal: true

module Coordinator::Write
  class RepositoryRegistrationLoader
    EVENT_TYPES = %w[
      RepositoryRegistered
      RepositoryDisplayNameChanged
      RepositoryPathAdded
      RepositoryPathRemoved
      RepositoryRemoteAdded
      RepositoryRemoteRemoved
    ].freeze

    def initialize(
      event_store:,
      schema_registry: EventSchemaRegistry.new,
      stream_factory: StreamFactory.new
    )
      @event_store = event_store
      @schema_registry = schema_registry
      @stream_factory = stream_factory
    end

    def call(repository_id)
      event = @event_store.read(
        @stream_factory.repository(repository_id),
        EventReadCriteria.new(event_types: EVENT_TYPES, maximum_count: 1_024, direction: :asc)
      )
      fold(event)
    end

    private

    def fold(events)
      state = nil
      events.each do |event|
        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        state = case payload
        when Events::RepositoryRegisteredV2
          RepositoryRegistrationV2.new(
            repository_id: payload.repository_id,
            scope: payload.scope,
            repository_key: payload.repository_key,
            display_name: nil,
            paths: [],
            remotes: []
          )
        when Events::RepositoryDisplayNameChangedV1
          replace(state, display_name: payload.display_name)
        when Events::RepositoryPathAddedV1
          replace(state, paths: (state.paths + [ payload.path ]).uniq)
        when Events::RepositoryPathRemovedV1
          replace(state, paths: state.paths - [ payload.path ])
        when Events::RepositoryRemoteAddedV1
          replace(state, remotes: (state.remotes + [ payload.remote ]).uniq)
        when Events::RepositoryRemoteRemovedV1
          replace(state, remotes: state.remotes - [ payload.remote ])
        else
          state
        end
      end
      state
    end

    def replace(state, attributes)
      RepositoryRegistrationV2.new(state.to_h.merge(attributes))
    end
  end
end
