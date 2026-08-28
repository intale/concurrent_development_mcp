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

    class AttemptHistoryArguments < Value
      attribute :work_item_id, Types::Identifier
      attribute :after_authorized_global_position, Types::Integer.constrained(gteq: 0)
      attribute :limit, Types::Integer.constrained(gteq: 1, lteq: 100)
    end

    class CoordinationListArguments < Value
      attribute :scope, Types::String.constrained(min_size: 1, max_size: 500)
      attribute :repository_id, Types::RepositoryId.optional
      attribute :statuses,
                Types::Array.of(Types::String.enum("planning", "active", "completed"))
                  .constrained(min_size: 1, max_size: 3)
      attribute :cursor, CoordinationPageV1::Cursor
      attribute :limit,
                Types::Integer.constrained(
                  gteq: 1,
                  lteq: Types::COORDINATION_DISCOVERY_MAXIMUM_ITEMS
                )
    end

    class DecisionListArguments < Value
      attribute :repository_id, Types::RepositoryId
      attribute :topic_id, Types::Identifier.optional
      attribute :policy_status, Types::DecisionPolicyStatus.optional
      attribute :after_decision_id, Types::Identifier
      attribute :limit,
                Types::Integer.constrained(
                  gteq: 1,
                  lteq: Types::DECISION_DISCOVERY_MAXIMUM_ITEMS
                )
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
                AttemptHistoryArguments |
                CoordinationListArguments |
                DecisionListArguments |
                DevelopmentArtifactLocatorArguments

    attribute :tool, Types::Identifier
    attribute :arguments, Arguments
  end
end
