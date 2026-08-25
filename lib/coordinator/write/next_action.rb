# frozen_string_literal: true

module Coordinator::Write
  class NextAction < Value
    class ChangeSetArguments < Value
      attribute :change_set_id, Types::Identifier
    end

    class AttemptArguments < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
    end

    class GuidanceArguments < Value
      attribute :message_id, Types::Identifier
    end

    class InterpretationListArguments < Value
      attribute :message_id, Types::Identifier
    end

    class DecisionArguments < Value
      attribute :decision_id, Types::Identifier
    end

    class AgentChoiceArguments < Value
      attribute :choice_id, Types::Identifier
    end

    class CandidateArguments < Value
      attribute :candidate_id, Types::Identifier
    end

    class VerificationObligationArguments < Value
      attribute :obligation_id, Types::Identifier
    end

    class MergeSnapshotArguments < Value
      attribute :merge_snapshot_id, Types::Identifier
    end

    class ReleaseSetArguments < Value
      attribute :release_set_id, Types::Identifier
    end

    class SkillArguments < Value
      attribute :name, Types::SkillName
      attribute :scope, Types::SkillScope
    end

    class OperationBatchArguments < Value
      attribute :batch_id, Types::OperationBatchId
    end

    class DevelopmentArtifactArguments < Value
      attribute :artifact_id, Types::DevelopmentArtifactId
    end

    class DecisionResolutionArguments < Value
      attribute :topic_id, Types::AgentChoiceType
      attribute :context, DecisionContexts::QueryContextV1
    end

    Arguments = ChangeSetArguments |
                AttemptArguments |
                GuidanceArguments |
                InterpretationListArguments |
                DecisionArguments |
                AgentChoiceArguments |
                CandidateArguments |
                VerificationObligationArguments |
                MergeSnapshotArguments |
                ReleaseSetArguments |
                SkillArguments |
                OperationBatchArguments |
                DevelopmentArtifactArguments |
                DecisionResolutionArguments

    attribute :tool, Types::Identifier
    attribute :arguments, Arguments
  end
end
