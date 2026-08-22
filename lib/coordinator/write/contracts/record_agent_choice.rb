# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class RecordAgentChoice < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, eql?: "agent")
          required(:id).filled(:string)
        end
        required(:choice_id).filled(:string)
        required(:choice_type).filled(:string, eql?: "testing.framework")
        required(:selected).hash do
          required(:option_id).filled(:string)
          required(:summary).filled(:string)
        end
        required(:alternatives).array(:hash) do
          required(:option_id).filled(:string)
          required(:summary).filled(:string)
        end
        required(:reason_summary).filled(:string)
        required(:context).hash(DecisionContextSchemas::QUERY_CONTEXT)
        required(:decision_context).hash(DecisionContextSchemas::CONTEXT)
      end

      rule(:command_id, :choice_id) do
        %i[command_id choice_id].each do |name|
          identifier = values[name]
          key(name).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(identifier)
        end
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value[:id])
      end

      rule(:selected, :alternatives) do
        options = [ values[:selected] ] + values[:alternatives]
        if values[:alternatives].length > 10
          key(:alternatives).failure("must contain at most 10 entries")
        end
        unless options.map { _1[:option_id] }.uniq.length == options.length
          key(:alternatives).failure("must not repeat the selected or another alternative option")
        end
        options.each_with_index do |option, index|
          prefix = index.zero? ? [ :selected ] : [ :alternatives, index - 1 ]
          unless Types::IDENTIFIER_PATTERN.match?(option[:option_id])
            key(prefix + [ :option_id ]).failure("must be a valid identifier")
          end
          unless Text.valid?(option[:summary], max_size: 500)
            key(prefix + [ :summary ]).failure("must be nonblank UTF-8 text of at most 500 characters")
          end
        end
      end

      rule(:reason_summary) do
        unless Text.valid?(value, max_size: 1_000)
          key.failure("must be nonblank UTF-8 text of at most 1000 characters")
        end
      end

      rule(:context) do
        key([ :context, :paths ]).failure("must contain at most 32 unique paths") unless bounded_unique?(value[:paths], 32)
        value[:paths].each_with_index do |path, index|
          next if Types::RESOURCE_PATH_PATTERN.match?(path)

          key([ :context, :paths, index ]).failure("must be a valid resource path")
        end
        %i[workspace_id environment].each do |name|
          next unless value[name]
          next if Types::IDENTIFIER_PATTERN.match?(value[name])

          key([ :context, name ]).failure("must be a valid identifier")
        end
      end

      rule(:decision_context) do
        begin
          context = DecisionContexts::ContextV1.new(value)
          expected = CanonicalJson.new.sha256(context.document.to_h)
          key([ :decision_context, :digest ]).failure("must match the canonical document") unless context.digest == expected
        rescue Dry::Struct::Error, Dry::Types::ConstraintError => error
          key.failure("must satisfy DecisionContextV1: #{error.message}")
        end
      end

      rule(:context, :decision_context) do
        normalized = values[:context].merge(
          workspace_id: values[:context][:workspace_id],
          environment: values[:context][:environment],
          paths: values[:context][:paths].uniq.sort_by(&:b)
        )
        query = values.dig(:decision_context, :document, :query_context)
        key(:decision_context).failure("query_context must match context") unless query == normalized
      end

      private

      def bounded_unique?(values, maximum)
        values.length <= maximum && values.uniq.length == values.length
      end
    end
  end
end
