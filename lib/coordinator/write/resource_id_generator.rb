# frozen_string_literal: true

module Coordinator::Write
  class ResourceIdGenerator
    def initialize(id_generator: IdGenerator.new)
      @id_generator = id_generator
    end

    def call
      Types::ResourceId[@id_generator.uuid_v7]
    end
  end
end
