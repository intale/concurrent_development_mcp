# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class SkillPublicationV3 < EventMetadata
      attribute :content_digest, Types::Sha256Digest
    end
  end
end
