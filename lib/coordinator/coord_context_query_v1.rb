# frozen_string_literal: true

module Coordinator
  class CoordContextQueryV1 < Value
    attribute :scope_kind, Types::String.enum("change_set", "work_item", "attempt")
    attribute :scope_id, Types::Identifier
    attribute :after_command_id, Types::Identifier.optional
    attribute :context_token, Types::Sha256Digest.optional
  end
end
