# frozen_string_literal: true

module Coordinator::Read
  class ResourceGetQueryV1 < Value
    attribute :resource_id, Types::ResourceId
  end
end
