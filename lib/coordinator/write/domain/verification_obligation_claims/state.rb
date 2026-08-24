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

        def next_fencing_token
          claim ? claim.fencing_token + 1 : 1
        end
      end
    end
  end
end
