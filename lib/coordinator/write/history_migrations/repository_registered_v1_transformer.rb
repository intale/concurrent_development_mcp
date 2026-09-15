# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class RepositoryRegisteredV1Transformer
      include Dry::Monads[:result]

      def initialize(
        stream_identity_allocator:,
        compound_marker_builder: CompoundMarkerBuilder.new,
        natural_key_marker: Repositories::NaturalKeyMarker.new
      )
        @stream_identity_allocator = stream_identity_allocator
        @compound_marker_builder = compound_marker_builder
        @natural_key_marker = natural_key_marker
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "DevelopmentPlanning",
          target_stream_name: "Repository",
          identity_role: "repository"
        )
        return allocation if allocation.failure?

        target_stream = allocation.value!.target_stream
        target_id = target_stream.stream_id
        Success(
          registration_facts(source_payload, target_stream:, target_id:)
        )
      end

      private

      def registration_facts(source, target_stream:, target_id:)
        facts = [
          fact(
            target_stream:,
            event: Events::RepositoryRegisteredV2.new(
              repository_id: target_id,
              scope: source.scope,
              repository_key: source.repository_key
            ),
            markers: registration_markers(source, target_id:),
            step_name: "register-repository"
          )
        ]
        facts << display_name_fact(source, target_stream:, target_id:) if source.display_name
        source.paths.uniq.each_with_index do |path, index|
          facts << path_fact(path, index:, source:, target_stream:, target_id:)
        end
        source.remotes.uniq.each_with_index do |remote, index|
          facts << remote_fact(remote, index:, source:, target_stream:, target_id:)
        end
        facts
      end

      def display_name_fact(source, target_stream:, target_id:)
        fact(
          target_stream:,
          event: Events::RepositoryDisplayNameChangedV1.new(
            repository_id: target_id,
            display_name: source.display_name
          ),
          markers: common_markers(source, target_id:),
          step_name: "define-repository-display-name"
        )
      end

      def path_fact(path, index:, source:, target_stream:, target_id:)
        fact(
          target_stream:,
          event: Events::RepositoryPathAddedV1.new(repository_id: target_id, path:),
          markers: common_markers(source, target_id:),
          step_name: format("add-repository-path-%02d", index + 1)
        )
      end

      def remote_fact(remote, index:, source:, target_stream:, target_id:)
        fact(
          target_stream:,
          event: Events::RepositoryRemoteAddedV1.new(repository_id: target_id, remote:),
          markers: common_markers(source, target_id:),
          step_name: format("add-repository-remote-%02d", index + 1)
        )
      end

      def fact(target_stream:, event:, markers:, step_name:)
        TransformedFactV1.new(target_stream:, event:, markers:, step_name:)
      end

      def registration_markers(source, target_id:)
        common_markers(source, target_id:) + [
          @compound_marker_builder.call(
            CompoundMarkerDefinitionV1.new(
              purpose: "repository-scope",
              components: [ "dimension:scope", "scope:#{source.scope}" ]
            )
          ).marker,
          @compound_marker_builder.call(
            CompoundMarkerDefinitionV1.new(
              purpose: "scoped-repository",
              components: [ "scope:#{source.scope}", "repository:#{target_id}" ]
            )
          ).marker,
          @natural_key_marker.call(scope: source.scope, repository_key: source.repository_key).marker
        ]
      end

      def common_markers(source, target_id:)
        [ "repository:#{target_id}", "repository-key:#{source.repository_key}" ]
      end
    end
  end
end
