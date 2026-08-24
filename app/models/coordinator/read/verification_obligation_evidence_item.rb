# frozen_string_literal: true

module Coordinator::Read
  class VerificationObligationEvidenceItem < ApplicationRecord
    self.primary_key = "evidence_id"
  end
end
