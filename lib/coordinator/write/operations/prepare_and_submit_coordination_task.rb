# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareAndSubmitCoordinationTask
      def initialize(preparer:, submitter:)
        @preparer = preparer
        @submitter = submitter
      end

      def call(input)
        @preparer.call(input).bind { @submitter.call(_1) }
      end
    end
  end
end
