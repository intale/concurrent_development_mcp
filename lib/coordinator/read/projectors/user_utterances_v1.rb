# frozen_string_literal: true

module Coordinator::Read::Projectors
  class UserUtterancesV1
    def call(events)
      ApplicationRecord.transaction do
        patches = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :message_id ])
        ids = events.select { _1.type == "GuidanceMessageAnchored" }.map { _1.data.fetch("message_id") }.uniq
        anchors = ids.empty? ? {} : Coordinator::Read::UserUtterance.where(message_id: ids).pluck(:message_id, :anchors).to_h
        fold = Coordinator::Read::Projections::UserUtterances.new(patches:, anchors:)
        events.each { fold.apply(_1) }
        Coordinator::Read::Repositories::BatchWriter.new(model: Coordinator::Read::UserUtterance, patches:).call
      end
      nil
    end
  end
end
