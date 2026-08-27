# frozen_string_literal: true

module Coordinator::Processes
  module InternalCommandIdBuilder
    module_function

    def call(identity)
      Types::InternalCommandId["internal:#{identity}"]
    end
  end
end
