# frozen_string_literal: true

module Coordinator::Read::Web
  class CoordinationDashboardQueryV1
    KINDS = %w[change_sets work_items dependencies].freeze
    LATEST_UPDATE_SORTS = %w[newest_first oldest_first].freeze
    WORK_ITEM_SORTS = %w[updated_at_desc updated_at_asc status_asc latest_activity_desc].freeze

    class Page < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :kind, Coordinator::Shared::Types::String.enum(*KINDS)
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :after_id, Coordinator::Shared::Types::String.optional
      attribute :after_sort_value, Coordinator::Shared::Types::String.optional
      attribute :sort,
                Coordinator::Shared::Types::String.default("newest_first".freeze).enum(*LATEST_UPDATE_SORTS)
      attribute :presentation_statuses,
                Coordinator::Shared::Types::Array.of(
                  Coordinator::Shared::Types::String.enum(
                    "pending",
                    "ready",
                    "assigned",
                    "running",
                    "completed"
                  )
                ).constrained(max_size: 5)
      attribute :work_item_sort, Coordinator::Shared::Types::String.enum(*WORK_ITEM_SORTS)
      attribute :blocking, Coordinator::Shared::Types::Strict::Bool.optional
      attribute :domain_status, Coordinator::Shared::Types::String.optional
      attribute :change_set_id, Coordinator::Shared::Types::String.optional
      attribute :agent_id, Coordinator::Shared::Types::String.optional
    end

    class Detail < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :kind, Coordinator::Shared::Types::String.enum(*KINDS)
      attribute :id, Coordinator::Shared::Types::String
    end
  end
end
