# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationClaims
      class State < Value
        attribute :obligation, Types.Instance(Events::VerificationObligationCreatedV1).optional
        attribute :obligation_event, Types.Instance(EventReference).optional
        attribute :claim, Types.Instance(Events::VerificationObligationClaimedV1).optional

        def self.initial
          new(obligation: nil, obligation_event: nil, claim: nil)
        end

        def absent?
          obligation.nil?
        end

        def active_at?(timestamp)
          !claim.nil? && claim.expires_at > timestamp
        end

        def active_claim_at(timestamp)
          return unless active_at?(timestamp)

          claim
        end

        def next_fencing_token
          claim ? claim.fencing_token + 1 : 1
        end

        def scope_markers
          return [] unless obligation

          source = obligation.source_candidate
          target = obligation.target_candidate
          [
            "verification-obligation:#{obligation.obligation_id}",
            "verification-obligation-kind:#{obligation.kind}",
            "verification-obligation-status:#{obligation.status}",
            "change-set:#{obligation.change_set_id}",
            "source-candidate:#{source.candidate_id}",
            "target-candidate:#{target.candidate_id}",
            "candidate:#{source.candidate_id}",
            "candidate:#{target.candidate_id}",
            "work-item:#{source.work_item_id}",
            "work-item:#{target.work_item_id}",
            "repository:#{source.repository_id}",
            "repository:#{target.repository_id}",
            "enforcement:#{obligation.enforcement}",
            "decision:#{obligation.policy.head.decision_id}"
          ].freeze
        end
      end
    end
  end
end
