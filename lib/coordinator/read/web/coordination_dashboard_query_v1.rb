# frozen_string_literal: true

module Coordinator::Read::Web
  class CoordinationDashboardQueryV1 < Coordinator::Shared::Value
    attribute :repository_id, Coordinator::Shared::Types::UuidV7
    attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
    attribute :change_set_offset, Coordinator::Shared::Types::Integer.constrained(gteq: 0)
    attribute :work_item_offset, Coordinator::Shared::Types::Integer.constrained(gteq: 0)
    attribute :dependency_offset, Coordinator::Shared::Types::Integer.constrained(gteq: 0)
    attribute :presentation_statuses,
              Coordinator::Shared::Types::Array.of(
                Coordinator::Shared::Types::String.enum("pending", "ready", "assigned", "running", "completed")
              ).constrained(max_size: 5)
    attribute :work_item_sort,
              Coordinator::Shared::Types::String.enum("work_item_id_asc", "status_asc", "latest_activity_desc")
    attribute :blocking, Coordinator::Shared::Types::Strict::Bool.optional
  end
end
