# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DecisionResolve < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:topic_id).filled(:string)
        required(:context).hash do
          optional(:workspace_id).maybe(:string)
          required(:repository_id).filled(:string)
          required(:change_set_id).filled(:string)
          required(:work_item_id).filled(:string)
          required(:attempt_id).filled(:string)
          required(:phase).filled(:string)
          required(:language).filled(:string)
          required(:paths).array(:string)
          optional(:environment).maybe(:string)
          required(:agent_role).filled(:string)
        end
      end

      rule(:topic_id) do
        key.failure("must be testing.framework") unless value == "testing.framework"
      end

      rule(:context) do
        report = ->(path, message) { key(path).failure(message) }
        validate_identifier(value, :workspace_id, report) if value[:workspace_id]
        unless Types::REPOSITORY_ID_PATTERN.match?(value[:repository_id])
          report.call([ :context, :repository_id ], "must be a valid repository identifier")
        end
        %i[change_set_id work_item_id attempt_id language environment agent_role].each do |name|
          validate_identifier(value, name, report) if value[name]
        end
        report.call([ :context, :phase ], "must be implementation") unless value[:phase] == "implementation"
        validate_paths(value[:paths], report)
      end

      private

      def validate_identifier(context, name, report)
        return if Types::IDENTIFIER_PATTERN.match?(context[name])

        report.call([ :context, name ], "must be a valid identifier")
      end

      def validate_paths(paths, report)
        report.call([ :context, :paths ], "must contain at most 32 paths") if paths.length > 32
        paths.each_with_index do |path, index|
          next if Types::RESOURCE_PATH_PATTERN.match?(path)

          report.call([ :context, :paths, index ], "must be a valid resource path")
        end
      end
    end
  end
end
