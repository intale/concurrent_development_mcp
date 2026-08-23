# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class InvalidHistory < StandardError
      attr_reader :reason, :evidence

      def initialize(reason:, evidence:)
        @reason = reason
        @evidence = evidence.freeze
        super("AgentChoice impact history is invalid: #{reason}")
      end
    end
  end
end
