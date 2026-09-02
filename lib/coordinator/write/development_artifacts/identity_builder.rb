# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class IdentityBuilder
      def initialize(id_generator: IdGenerator.new)
        @id_generator = id_generator
      end

      def call
        @id_generator.uuid_v7
      end
    end
  end
end
