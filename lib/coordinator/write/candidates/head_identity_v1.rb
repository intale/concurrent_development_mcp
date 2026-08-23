# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class HeadIdentityV1 < Value
      attribute :document, Types.Instance(HeadIdentityDocumentV1)
      attribute :registry_id, Types::Sha256Digest
      attribute :marker, Types::Marker
    end
  end
end
