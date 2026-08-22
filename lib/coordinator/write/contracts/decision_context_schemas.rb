# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    module DecisionContextSchemas
      EVENT_REFERENCE = Dry::Schema.Params do
        config.validate_keys = true
        required(:event_id).filled(:string, format?: Types::UUID_V7_PATTERN)
        required(:type).filled(:string, format?: Types::IDENTIFIER_PATTERN)
        required(:stream_context).filled(:string, format?: Types::IDENTIFIER_PATTERN)
        required(:stream_name).filled(:string, format?: Types::IDENTIFIER_PATTERN)
        required(:stream_id).filled(:string, format?: Types::IDENTIFIER_PATTERN)
        required(:stream_revision).filled(:integer, gteq?: 0)
      end

      DECISION_HEAD = Dry::Schema.Params do
        config.validate_keys = true
        required(:decision_id).filled(:string, format?: Types::IDENTIFIER_PATTERN)
        required(:decision_revision).filled(:integer, gteq?: 0)
        required(:event).hash(EVENT_REFERENCE)
      end

      PARTITION = Dry::Schema.Params do
        config.validate_keys = true
        required(:partition_id).filled(:string, format?: Types::IDENTIFIER_PATTERN)
        required(:topic_root).filled(:string, eql?: "testing")
        required(:anchor_kind).filled(:string, included_in?: Types::DECISION_PARTITION_ANCHOR_KINDS)
        required(:anchor_id).filled(:string, format?: Types::IDENTIFIER_PATTERN)
      end

      PARTITION_OBSERVATION = Dry::Schema.Params do
        config.validate_keys = true
        required(:partition).hash(PARTITION)
        required(:partition_revision).maybe(:integer, gteq?: 0)
        required(:event).maybe do
          hash(EVENT_REFERENCE)
        end
        required(:active_decisions).array(DECISION_HEAD)
      end

      QUERY_CONTEXT = Dry::Schema.Params do
        config.validate_keys = true
        optional(:workspace_id).maybe(:string)
        required(:repository_id).filled(:string, format?: Types::REPOSITORY_ID_PATTERN)
        required(:change_set_id).filled(:string, format?: Types::IDENTIFIER_PATTERN)
        required(:work_item_id).filled(:string, format?: Types::IDENTIFIER_PATTERN)
        required(:attempt_id).filled(:string, format?: Types::IDENTIFIER_PATTERN)
        required(:phase).filled(:string, eql?: "implementation")
        required(:language).filled(:string, format?: Types::IDENTIFIER_PATTERN)
        required(:paths).array(:string)
        optional(:environment).maybe(:string)
        required(:agent_role).filled(:string, format?: Types::IDENTIFIER_PATTERN)
      end

      DECISION_VALUE = Dry::Schema.Params do
        config.validate_keys = true
        required(:schema).filled(:string, included_in?: Types::DECISION_VALUE_SCHEMAS)
        required(:name).maybe(:string)
        required(:items).maybe { array(:string) }
        required(:target_kind).maybe(:string, included_in?: Types::MERGE_TARGET_KINDS)
        required(:target_id).maybe(:string)
        required(:action).maybe(:string, included_in?: Types::MERGE_ACTIONS)
      end

      ENFORCEMENT = Dry::Schema.Params do
        config.validate_keys = true
        required(:level).filled(:string, included_in?: Types::ENFORCEMENT_LEVELS)
        required(:retroactivity).filled(:string, included_in?: Types::RETROACTIVITY_KINDS)
        required(:on_violation).filled(:string, included_in?: Types::VIOLATION_ACTIONS)
      end

      RESOLVED_DECISION = Dry::Schema.Params do
        config.validate_keys = true
        required(:head).hash(DECISION_HEAD)
        required(:definition_digest).filled(:string, format?: Types::SHA256_DIGEST_PATTERN)
        required(:topic_id).filled(:string, eql?: "testing.framework")
        required(:effect).filled(:string, included_in?: Types::DECISION_EFFECTS)
        required(:modality).filled(:string, included_in?: Types::DECISION_MODALITIES)
        required(:value).hash(DECISION_VALUE)
        required(:enforcement).hash(ENFORCEMENT)
        required(:anchor_kind).filled(
          :string,
          included_in?: DecisionContexts::ResolvedDecisionV1::ANCHOR_KINDS
        )
        required(:anchor_rank).filled(:integer, gteq?: 1, lteq?: 5)
        required(:applicability_reasons).array(:string)
      end

      SHADOWED_DECISION = Dry::Schema.Params do
        config.validate_keys = true
        required(:decision).hash(RESOLVED_DECISION)
        required(:reason).filled(:string, eql?: "less_specific")
      end

      CONFLICT = Dry::Schema.Params do
        config.validate_keys = true
        required(:decisions).array(RESOLVED_DECISION)
        required(:reason).filled(:string, eql?: "tied_most_specific")
      end

      DOCUMENT = Dry::Schema.Params do
        config.validate_keys = true
        required(:schema).filled(:string, eql?: "decision-context/v1")
        required(:resolution_policy).filled(:string, eql?: "testing-framework-resolution/v1")
        required(:topic_id).filled(:string, eql?: "testing.framework")
        required(:query_context).hash(QUERY_CONTEXT)
        required(:partitions).array(PARTITION_OBSERVATION)
        required(:effective_decision).maybe do
          hash(RESOLVED_DECISION)
        end
        required(:shadowed_decisions).array(SHADOWED_DECISION)
        required(:conflict).maybe do
          hash(CONFLICT)
        end
      end

      CONTEXT = Dry::Schema.Params do
        config.validate_keys = true
        required(:document).hash(DOCUMENT)
        required(:digest).filled(:string, format?: Types::SHA256_DIGEST_PATTERN)
        required(:resolved_at).filled(:string, format?: Types::TIMESTAMP_PATTERN)
      end
    end
  end
end
