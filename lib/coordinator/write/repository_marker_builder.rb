# frozen_string_literal: true

module Coordinator::Write
  class RepositoryMarkerBuilder
    RESOURCE_BOUNDARY_MARKER_PURPOSE = "resource-boundary"

    def initialize(compound_marker_builder: CompoundMarkerBuilder.new)
      @compound_marker_builder = compound_marker_builder
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

    private

    def ancestor_paths(path)
      components = path.split("/")
      (1...components.length).map { components.first(_1).join("/") }
    end

    def path_marker(prefix, repository_id, path)
      digest = OpenSSL::Digest::SHA256.hexdigest("#{path.bytesize}:#{path}")
      @compound_marker_builder.call(
        CompoundMarkerDefinitionV1.new(
          purpose: RESOURCE_BOUNDARY_MARKER_PURPOSE,
          components: [
            "repository:#{repository_id}",
            "boundary-role:#{prefix}",
            "resource-path-digest:sha256:#{digest}"
          ]
        )
      ).marker
    end
  end
end
