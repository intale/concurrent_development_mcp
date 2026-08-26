# frozen_string_literal: true

module Coordinator::Read
  class NextAction < Value
    class ChangeSetArguments < Value
      attribute :change_set_id, Types::Identifier
    end

    class WorkItemArguments < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
    end

    class AttemptArguments < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
    end

    class WorkItemCompletionArguments < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :candidate_id, Types::Identifier
    end

    class DevelopmentArtifactLocatorArguments < Value
      attribute :scope, Types::DevelopmentArtifactScope
      attribute :source_kind, Types::DevelopmentArtifactSourceKind
      attribute :locator, Types::DevelopmentArtifactSourceLocator
      attribute? :source_revision, Types::DevelopmentArtifactSourceRevision.optional
      attribute :cursor, DevelopmentArtifactLocatorPageV1::Cursor
      attribute :limit,
                Types::Integer.constrained(
                  gteq: 1,
                  lteq: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
                )
    end

    Arguments = ChangeSetArguments |
                WorkItemArguments |
                AttemptArguments |
                WorkItemCompletionArguments |
                DevelopmentArtifactLocatorArguments

    attribute :tool, Types::Identifier
    attribute :arguments, Arguments
  end
end
