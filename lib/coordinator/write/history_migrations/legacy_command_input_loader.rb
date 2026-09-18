# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyCommandInputLoader
      def call(document)
        return document unless document.is_a?(Hash)

        attributes = document.transform_keys(&:to_sym)
        tool_name = attributes.fetch(:tool_name)
        definitions = Array(LegacyCommandInputDocuments::DEFINITIONS.fetch(tool_name))
        failure = nil
        definitions.each do |definition|
          begin
            return definition.new(attributes)
          rescue Dry::Struct::Error => error
            failure = error
          end
        end
        raise failure
      end
    end
  end
end
