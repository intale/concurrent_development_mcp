# frozen_string_literal: true

module Coordinator::Write
  module Events::OptimisticSagas
    class WorkIntentionSetRenewalFailedV1 < Events::Base
      contract type: "WorkIntentionSetRenewalFailed", version: 1

      attribute :renewal_id, Types::UuidV7
    end
  end
end
