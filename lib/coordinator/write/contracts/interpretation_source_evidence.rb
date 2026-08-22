# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class InterpretationSourceEvidence < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:source_message_id).filled(:string)
        required(:persisted_message_id).filled(:string)
        required(:source_text).filled(:string)
        required(:source_span).maybe do
          hash do
            required(:start_character).filled(:integer, gteq?: 0)
            required(:end_character).filled(:integer, gteq?: 0)
            required(:text).filled(:string)
          end
        end
      end

      rule(:source_message_id, :persisted_message_id) do
        key(:source_message_id).failure("does not match persisted guidance") unless values[:source_message_id] == values[:persisted_message_id]
      end

      rule(:source_text, :source_span) do
        span = values[:source_span]
        next unless span

        excerpt = values[:source_text].each_char.to_a[span[:start_character]...span[:end_character]]&.join
        key(:source_span).failure("does not match persisted guidance text") unless excerpt == span[:text]
      end
    end
  end
end
