# frozen_string_literal: true

module Coordinator::Write::ProjectionInitialization
  SourceState = Data.define(:definition, :stream, :source, :latest_revision, :existing_types, :history, :corrections_number)
end
