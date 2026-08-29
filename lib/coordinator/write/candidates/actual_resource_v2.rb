# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ActualResourceV2 < Value
      attribute :kind, Types::String.enum("file")
      attribute :path, Types::ResourcePath
      attribute :base_blob_oid, Types::GitOid.optional
    end
  end
end
