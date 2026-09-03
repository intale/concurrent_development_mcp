# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class ClassifierV1 < EventMetadata
      attribute :classifier, Types::Identifier
    end
  end
end
