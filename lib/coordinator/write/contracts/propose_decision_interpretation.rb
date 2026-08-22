# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ProposeDecisionInterpretation < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: Types::ACTOR_KINDS)
          required(:id).filled(:string)
        end
        required(:interpretation_id).filled(:string)
        required(:source_message_id).filled(:string)
        required(:source_span).maybe do
          hash do
            required(:start_character).filled(:integer, gteq?: 0)
            required(:end_character).filled(:integer, gteq?: 0)
            required(:text).filled(:string)
          end
        end
        required(:classifier).hash do
          required(:id).filled(:string)
          required(:version).filled(:string)
          required(:ontology_version).filled(:integer, eql?: 1)
          required(:confidence_millionths).filled(:integer, gteq?: 0, lteq?: 1_000_000)
        end
        required(:proposed_decision).hash do
          required(:statement_kind).filled(:string, included_in?: Types::STATEMENT_KINDS)
          required(:topic_id).filled(:string)
          required(:effect).maybe(:string, included_in?: Types::DECISION_EFFECTS)
          required(:modality).maybe(:string, included_in?: Types::DECISION_MODALITIES)
          required(:value).hash do
            required(:schema).filled(:string, included_in?: Types::DECISION_VALUE_SCHEMAS)
            required(:name).maybe(:string)
            required(:items).maybe { array(:string) }
            required(:target_kind).maybe(:string, included_in?: Types::MERGE_TARGET_KINDS)
            required(:target_id).maybe(:string)
            required(:action).maybe(:string, included_in?: Types::MERGE_ACTIONS)
          end
          required(:scope).maybe do
            hash do
              required(:workspace_id).maybe(:string)
              required(:repository_ids).array(:string)
              required(:branch_selectors).array(:string)
              required(:change_set_id).maybe(:string)
              required(:work_item_id).maybe(:string)
              required(:attempt_id).maybe(:string)
              required(:candidate_id).maybe(:string)
              required(:path_selectors).array(:string)
              required(:symbol_selectors).array(:string)
              required(:contract_selectors).array(:string)
              required(:schema_selectors).array(:string)
              required(:environments).array(:string)
              required(:agent_roles).array(:string)
            end
          end
          required(:conditions).hash do
            required(:phases).array(:string, included_in?: Types::DECISION_PHASES)
            required(:languages).array(:string)
            required(:tags).array(:string)
            required(:repository_kinds).array(:string)
            required(:artifact_kinds).array(:string)
            required(:environments).array(:string)
          end
          required(:validity).hash do
            required(:valid_from).maybe(:string)
            required(:valid_until).maybe(:string)
            required(:until_event).maybe do
              hash do
                required(:event_type).filled(:string)
                required(:stream_context).filled(:string)
                required(:stream_name).filled(:string)
                required(:stream_id).filled(:string)
              end
            end
          end
          required(:authority).hash do
            required(:actor_id).filled(:string)
            required(:role).filled(:string)
          end
          required(:enforcement).hash do
            required(:level).filled(:string, included_in?: Types::ENFORCEMENT_LEVELS)
            required(:retroactivity).filled(:string, included_in?: Types::RETROACTIVITY_KINDS)
            required(:on_violation).filled(:string, included_in?: Types::VIOLATION_ACTIONS)
          end
          required(:relations).hash do
            required(:corrects).array(:string)
            required(:supersedes).array(:string)
            required(:exception_to).array(:string)
            required(:revokes).array(:string)
          end
        end
        required(:ambiguities).array(:hash) do
          required(:field).filled(:string)
          required(:code).filled(:string)
          required(:description).filled(:string)
          required(:options).array(:string)
        end
      end

      rule(:command_id, :interpretation_id, :source_message_id) do
        values.each do |name, identifier|
          next unless identifier.is_a?(String)
          next if Types::IDENTIFIER_PATTERN.match?(identifier)

          key(name).failure("must be a valid identifier")
        end
      end

      rule(:actor) do
        report = ->(path, message) { key(path).failure(message) }
        validate_identifier(value[:id], [ :actor, :id ], report)
      end

      rule(:source_span) do
        next if value.nil?

        key([ :source_span, :end_character ]).failure("must be greater than start_character") unless value[:end_character] > value[:start_character]
        report = ->(path, message) { key(path).failure(message) }
        validate_text(value[:text], [ :source_span, :text ], 16_000, report)
      end

      rule(:classifier) do
        report = ->(path, message) { key(path).failure(message) }
        validate_identifier(value[:id], [ :classifier, :id ], report)
        validate_text(value[:version], [ :classifier, :version ], 200, report)
      end

      rule(:proposed_decision) do
        report = ->(path, message) { key(path).failure(message) }
        validate_identifier(value[:topic_id], [ :proposed_decision, :topic_id ], report)
        validate_decision_value(value[:value], report)
        validate_scope(value[:scope], report) if value[:scope]
        validate_conditions(value[:conditions], report)
        validate_validity(value[:validity], report)
        validate_identifier(value.dig(:authority, :actor_id), [ :proposed_decision, :authority, :actor_id ], report)
        validate_identifier(value.dig(:authority, :role), [ :proposed_decision, :authority, :role ], report)
        validate_relations(value[:relations], report)
      end

      rule(:ambiguities) do
        key.failure("must contain at most 20 entries") if value.length > 20
        report = ->(path, message) { key(path).failure(message) }

        value.each_with_index do |ambiguity, index|
          validate_identifier(ambiguity[:field], [ :ambiguities, index, :field ], report)
          validate_identifier(ambiguity[:code], [ :ambiguities, index, :code ], report)
          validate_text(ambiguity[:description], [ :ambiguities, index, :description ], 500, report)
          validate_string_collection(ambiguity[:options], [ :ambiguities, index, :options ], max_size: 10, report:)
        end
      end

      private

      def validate_decision_value(value, report)
        fields = {
          "named-choice/v1" => %i[name],
          "string-set/v1" => %i[items],
          "target-action/v1" => %i[target_kind action]
        }.fetch(value[:schema], [])
        optional = %i[name items target_kind target_id action]

        fields.each do |field|
          report.call([ :proposed_decision, :value, field ], "must be present for #{value[:schema]}") if value[field].nil?
        end
        (optional - fields - (value[:schema] == "target-action/v1" ? [ :target_id ] : [])).each do |field|
          report.call([ :proposed_decision, :value, field ], "must be null for #{value[:schema]}") unless value[field].nil?
        end

        validate_text(value[:name], [ :proposed_decision, :value, :name ], 200, report) if value[:name]
        validate_string_collection(value[:items], [ :proposed_decision, :value, :items ], max_size: 100, min_size: 1, report:) if value[:items]
        validate_identifier(value[:target_id], [ :proposed_decision, :value, :target_id ], report) if value[:target_id]
      end

      def validate_scope(scope, report)
        identifiers = %i[workspace_id change_set_id work_item_id attempt_id candidate_id]
        identifiers.each do |field|
          validate_identifier(scope[field], [ :proposed_decision, :scope, field ], report) if scope[field]
        end
        validate_repository_ids(scope[:repository_ids], [ :proposed_decision, :scope, :repository_ids ], report)
        %i[branch_selectors symbol_selectors contract_selectors schema_selectors environments agent_roles].each do |field|
          validate_identifier_collection(scope[field], [ :proposed_decision, :scope, field ], report:)
        end
        validate_path_collection(scope[:path_selectors], [ :proposed_decision, :scope, :path_selectors ], report)
      end

      def validate_conditions(conditions, report)
        report.call([ :proposed_decision, :conditions, :phases ], "must contain at most 5 unique entries") unless bounded_unique?(conditions[:phases], 5)
        %i[languages tags repository_kinds artifact_kinds environments].each do |field|
          validate_identifier_collection(conditions[field], [ :proposed_decision, :conditions, field ], report:)
        end
      end

      def validate_validity(validity, report)
        %i[valid_from valid_until].each do |field|
          timestamp = validity[field]
          next if timestamp.nil? || Types::TIMESTAMP_PATTERN.match?(timestamp)

          report.call([ :proposed_decision, :validity, field ], "must be a UTC timestamp with microseconds")
        end
        if validity[:valid_from] && validity[:valid_until] && validity[:valid_until] <= validity[:valid_from]
          report.call([ :proposed_decision, :validity, :valid_until ], "must be later than valid_from")
        end
        until_event = validity[:until_event]
        return unless until_event

        until_event.each do |field, identifier|
          validate_identifier(identifier, [ :proposed_decision, :validity, :until_event, field ], report)
        end
      end

      def validate_relations(relations, report)
        relations.each do |field, identifiers|
          validate_identifier_collection(identifiers, [ :proposed_decision, :relations, field ], max_size: 20, report:)
        end
        populated = relations.values.count { !_1.empty? }
        report.call([ :proposed_decision, :relations ], "must use at most one relation kind") if populated > 1
      end

      def validate_identifier_collection(values, path, max_size: 100, report:)
        report.call(path, "must contain at most #{max_size} unique entries") unless bounded_unique?(values, max_size)
        values.each_with_index { |identifier, index| validate_identifier(identifier, path + [ index ], report) }
      end

      def validate_repository_ids(values, path, report)
        report.call(path, "must contain at most 100 unique entries") unless bounded_unique?(values, 100)
        values.each_with_index do |identifier, index|
          report.call(path + [ index ], "must be a valid repository identifier") unless Types::REPOSITORY_ID_PATTERN.match?(identifier)
        end
      end

      def validate_path_collection(values, path, report)
        report.call(path, "must contain at most 100 unique entries") unless bounded_unique?(values, 100)
        values.each_with_index do |selector, index|
          report.call(path + [ index ], "must be a valid path selector") unless Types::RESOURCE_PATH_PATTERN.match?(selector)
        end
      end

      def validate_string_collection(values, path, max_size:, report:, min_size: 0)
        unless values.length.between?(min_size, max_size) && values.uniq.length == values.length
          report.call(path, "must contain #{min_size}..#{max_size} unique entries")
        end
        values.each_with_index { |entry, index| validate_text(entry, path + [ index ], 200, report) }
      end

      def validate_identifier(value, path, report)
        return if value.is_a?(String) && Types::IDENTIFIER_PATTERN.match?(value)

        report.call(path, "must be a valid identifier")
      end

      def validate_text(value, path, max_size, report)
        return if Text.valid?(value, max_size:)

        report.call(path, "must be nonblank UTF-8 text of at most #{max_size} characters")
      end

      def bounded_unique?(values, maximum)
        values.length <= maximum && values.uniq.length == values.length
      end
    end
  end
end
