# frozen_string_literal: true

module Coordinator::Write
  class RepositoryMarkerBuilder
    def initialize(
      compound_marker_builder: CompoundMarkerBuilder.new,
      resource_marker_codec: Coordinator::Shared::ResourceMarkerCodec.new
    )
      @compound_marker_builder = compound_marker_builder
      @resource_marker_codec = resource_marker_codec
    end

    def call(registration)
      scope = "scope:#{registration.scope}"
      repository = "repository:#{registration.repository_id}"
      identity = @compound_marker_builder.call(
        CompoundMarkerDefinitionV1.new(
          purpose: "scoped-repository",
          components: [ scope, repository ]
        )
      )

      [ scope, repository, identity.marker ]
    end

    def resource_event_markers(repository_id:, resource_kind:, resource_path:)
      overlap_paths = ancestor_paths(resource_path)
      overlap_paths << resource_path if resource_kind == "directory"

      [
        path_marker("resource-path", repository_id, resource_path),
        *overlap_paths.map { path_marker("resource-overlap", repository_id, _1) }
      ].uniq
    end

    def resource_boundary_markers(repository_id:, resource_kind:, resource_path:)
      paths = ancestor_paths(resource_path) + [ resource_path ]
      markers = paths.map { path_marker("resource-path", repository_id, _1) }
      markers << path_marker("resource-overlap", repository_id, resource_path) if resource_kind == "directory"
      markers.uniq
    end

    def work_intention_event_markers(repository_id:, resource_path:)
      paths = ancestor_paths(resource_path) + [ resource_path ]

      [
        path_marker("resource-exact", repository_id, resource_path),
        *paths.map { path_marker("resource-within", repository_id, _1) }
      ].uniq
    end

    def work_intention_boundary_markers(repository_id:, resource_kind:, resource_path:)
      markers = ancestor_paths(resource_path).map do |path|
        path_marker("resource-exact", repository_id, path)
      end
      marker_role = resource_kind == "directory" ? "resource-within" : "resource-exact"
      markers << path_marker(marker_role, repository_id, resource_path)
      markers.uniq
    end

    private

    def ancestor_paths(path)
      components = path.split("/")
      (1...components.length).map { components.first(_1).join("/") }
    end

    def path_marker(prefix, repository_id, path)
      @resource_marker_codec.boundary(
        repository_id:,
        role: prefix,
        normalized_path: path
      )
    end
  end
end
