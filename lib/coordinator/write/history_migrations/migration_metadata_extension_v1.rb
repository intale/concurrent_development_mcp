# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationMetadataExtensionV1 < Value
      attribute? :canonical_input_digest, Types::Sha256Digest.optional.default(nil)
    end
  end
end
