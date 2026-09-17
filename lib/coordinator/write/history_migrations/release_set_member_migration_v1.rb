# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class ReleaseSetMemberMigrationV1 < Value
      attribute :source_member, ReleaseSets::MemberEvidenceV1
      attribute :target_member, Events::ReleaseSetMemberAddedV1

      def source_repository_id
        source_member.repository_id
      end

      def target_repository_id
        target_member.repository_id
      end
    end
  end
end
