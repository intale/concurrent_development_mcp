# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class IdentityBuilder
      def initialize(id_generator: IdGenerator.new)
        @id_generator = id_generator
      end

      def call(name:, scope:)
        IdentityV1.new(skill_id: @id_generator.uuid_v7, name:, scope:)
      end
    end
  end
end
