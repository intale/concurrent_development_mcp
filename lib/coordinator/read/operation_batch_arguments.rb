# frozen_string_literal: true

module Coordinator::Read
  class OperationBatchArguments
    def call(document)
      canonical = document.to_h
      input = canonical.fetch(:input).to_h
      actor = input.fetch(:actor).to_h

      {
        command_id: canonical.fetch(:command_id),
        actor: {
          kind: actor.fetch(:actor_kind),
          id: actor.fetch(:actor_id)
        }
      }.merge(input.except(:actor))
    end
  end
end
