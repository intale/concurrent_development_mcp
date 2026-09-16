# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    module DevelopmentArtifactPropertySteps
      module_function

      def created
        "create-development-artifact"
      end

      def content
        "change-development-artifact-content-initial"
      end

      def property(role, source_kind)
        "change-development-artifact-#{role}-#{source_kind}"
      end

      def label_added(source_kind, index)
        format("add-development-artifact-label-#{source_kind}-%02d", index + 1)
      end

      def label_removed(source_kind, index)
        format("remove-development-artifact-label-#{source_kind}-%02d", index + 1)
      end
    end
  end
end
