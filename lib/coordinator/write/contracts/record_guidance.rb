# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class RecordGuidance < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: Types::ACTOR_KINDS)
          required(:id).filled(:string)
        end
        required(:message_id).filled(:string)
        required(:conversation_id).filled(:string)
        required(:source).filled(:string, included_in?: Types::GUIDANCE_SOURCES)
        required(:text).filled(:string)
        required(:anchors).hash do
          required(:repository_ids).array(:string)
          required(:change_set_id).maybe(:string)
          required(:work_item_id).maybe(:string)
          required(:attempt_id).maybe(:string)
        end
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:message_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:conversation_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end

      rule(:text) do
        key.failure("must be nonblank UTF-8 text of at most 16000 characters") unless Text.valid?(value, max_size: 16_000)
      end

      rule(:anchors) do
        repository_ids = value[:repository_ids]
        next unless repository_ids.is_a?(Array)

        key([ :anchors, :repository_ids ]).failure("must contain at most 100 entries") if repository_ids.length > 100
        key([ :anchors, :repository_ids ]).failure("must not contain duplicates") if repository_ids.uniq.length != repository_ids.length

        repository_ids.each_index do |index|
          repository_id = repository_ids[index]
          next unless repository_id.is_a?(String)
          next if Types::REPOSITORY_ID_PATTERN.match?(repository_id)

          key([ :anchors, :repository_ids, index ]).failure("must be a valid repository identifier")
        end

        %i[change_set_id work_item_id attempt_id].each do |attribute|
          identifier = value[attribute]
          next if identifier.nil? || !identifier.is_a?(String)
          next if Types::IDENTIFIER_PATTERN.match?(identifier)

          key([ :anchors, attribute ]).failure("must be a valid identifier or null")
        end
      end
    end
  end
end
