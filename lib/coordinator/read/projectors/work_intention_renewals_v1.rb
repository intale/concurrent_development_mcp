# frozen_string_literal: true

module Coordinator::Read::Projectors
  class WorkIntentionRenewalsV1
    MEMBER_EVENTS = %w[WorkIntentionRenewalAssigned WorkIntentionRenewalCompleted WorkIntentionRenewalFailed].freeze

    def call(events)
      ApplicationRecord.transaction do
        patches = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :renewal_id ])
        ids = events.select { MEMBER_EVENTS.include?(_1.type) }.map { _1.data.fetch("renewal_id") }.uniq
        members = ids.empty? ? {} : Coordinator::Read::WorkIntentionRenewal.where(renewal_id: ids).pluck(:renewal_id, :members).to_h
        fold = Coordinator::Read::Projections::WorkIntentionRenewals.new(patches:, members:)
        events.each { fold.apply(_1) }
        Coordinator::Read::Repositories::BatchWriter.new(model: Coordinator::Read::WorkIntentionRenewal, patches:).call
      end
      nil
    end
  end
end
