# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AdjudicateDecisionInterpretation < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: Types::ACTOR_KINDS)
          required(:id).filled(:string)
        end
        required(:source_message_id).filled(:string)
        required(:interpretation_id).filled(:string)
        required(:action).filled(:string, included_in?: Types::INTERPRETATION_ADJUDICATION_ACTIONS)
        required(:rationale).hash do
          required(:code).filled(:string)
          required(:summary).filled(:string)
        end
        required(:clarification).maybe do
          hash do
            required(:status).filled(:string, included_in?: Types::INTERPRETATION_CLARIFICATION_STATUSES)
            required(:questions).array(:hash) do
              required(:field).filled(:string)
              required(:prompt).filled(:string)
              required(:options).array(:string)
            end
          end
        end
      end

      rule(:command_id, :source_message_id, :interpretation_id) do
        %i[command_id source_message_id interpretation_id].each do |name|
          identifier = values[name]
          key(name).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(identifier)
        end
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value[:id])
      end

      rule(:rationale) do
        key([ :rationale, :code ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value[:code])
        unless Text.valid?(value[:summary], max_size: 500)
          key([ :rationale, :summary ]).failure("must be nonblank UTF-8 text of at most 500 characters")
        end
      end

      rule(:action, :clarification) do
        if values[:action] == "request_clarification"
          key(:clarification).failure("must be present for request_clarification") if values[:clarification].nil?
        elsif values[:clarification]
          key(:clarification).failure("must be null unless action is request_clarification")
        end
      end

      rule(:clarification) do
        next if value.nil?

        questions = value[:questions]
        unless questions.length.between?(1, 20) && questions.uniq.length == questions.length
          key([ :clarification, :questions ]).failure("must contain 1..20 unique questions")
        end
        questions.each_with_index do |question, index|
          unless Types::IDENTIFIER_PATTERN.match?(question[:field])
            key([ :clarification, :questions, index, :field ]).failure("must be a valid identifier")
          end
          unless Text.valid?(question[:prompt], max_size: 500)
            key([ :clarification, :questions, index, :prompt ]).failure("must be nonblank UTF-8 text of at most 500 characters")
          end
          options = question[:options]
          unless options.length <= 10 && options.uniq.length == options.length && options.all? { Text.valid?(_1, max_size: 200) }
            key([ :clarification, :questions, index, :options ]).failure("must contain at most 10 unique bounded options")
          end
        end
      end
    end
  end
end
