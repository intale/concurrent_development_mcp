# frozen_string_literal: true

module Coordinator::Read
  class ReleaseSetGetQueryV1 < Value
    attribute :release_set_id, Types::Identifier
  end
end
