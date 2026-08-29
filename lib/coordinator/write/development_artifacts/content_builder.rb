# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class ContentBuilder
      def initialize(builder: Content::Builder.new)
        @builder = builder
      end

      def call(attributes)
        @builder.call(attributes)
      end
    end
  end
end
