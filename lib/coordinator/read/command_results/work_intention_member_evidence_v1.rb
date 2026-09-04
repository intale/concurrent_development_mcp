# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class WorkIntentionMemberEvidenceV1 < Value
      attribute :reference, Coordinator::Write::LeaseReferenceV2
      attribute :current_expires_at, Types::Timestamp
      attribute :before_command_expires_at, Types::Timestamp.optional
    end
  end
end
