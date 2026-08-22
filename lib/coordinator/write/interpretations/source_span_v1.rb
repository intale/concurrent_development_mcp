# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class SourceSpanV1 < Value
      attribute :start_character, Types::SourceCharacterIndex
      attribute :end_character, Types::SourceCharacterIndex
      attribute :text, Types::GuidanceText
    end
  end
end
