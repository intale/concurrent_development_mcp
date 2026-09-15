# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigratedCommandInputV1 < Value
      attribute :document, CommandInputDocuments::Type
      attribute :canonical_input_digest, Types::Sha256Digest
    end
  end
end
