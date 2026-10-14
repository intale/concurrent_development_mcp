# frozen_string_literal: true

module Coordinator::Write::Commands
  class CountCandidateCheckpoint < Coordinator::Write::Value
    attribute :command_id, Coordinator::Write::Types::UuidV7
    attribute :actor, Actor
    attribute :statistics_id, Coordinator::Write::Types::UuidV7
    attribute :source_event, Coordinator::Write::EventReference
  end
end
