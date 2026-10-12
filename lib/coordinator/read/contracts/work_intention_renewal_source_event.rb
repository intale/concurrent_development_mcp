# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class WorkIntentionRenewalSourceEvent < Dry::Validation::Contract
      params do
        required(:event_type).filled(:string, included_in?: Coordinator::Write::EventQueries::WORK_INTENTION_RENEWAL_HISTORY.event_types)
        required(:schema_version).filled(:integer, eql?: 1)
        required(:stream_context).filled(:string, eql?: "DevelopmentCoordination")
        required(:stream_name).filled(:string, eql?: "WorkIntentionSetRenewal")
        required(:stream_id).filled(Types::UuidV7)
        required(:stream_revision).filled(:integer, gteq?: 0)
        required(:global_position).filled(:integer, gteq?: 0)
        required(:correlation_id).filled(Types::UuidV7)
      end
    end
  end
end
