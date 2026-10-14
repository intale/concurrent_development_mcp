# frozen_string_literal: true

module Coordinator::Write::Commands
  class InitializeProjectionFacts < Coordinator::Write::Value
    attribute :command_id, Coordinator::Write::Types::Identifier
    attribute :actor, Actor
    attribute :source_event, Coordinator::Write::EventReference
  end
end
