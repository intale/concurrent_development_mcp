# frozen_string_literal: true

module Coordinator::Read::Web
  class ProjectReference
    class InvalidReference < ArgumentError; end

    def initialize(scope_contract: Coordinator::Read::Contracts::RepositoryList.new)
      @scope_contract = scope_contract
    end

    # A Project is an exact coordination scope, not a separately allocated entity.
    # Route-segment escaping belongs to the browser; no opaque identity wrapper is needed.
    def encode(scope:)
      validate_scope!(scope)
      scope
    end

    def decode(reference)
      validate_scope!(reference)
      reference
    end

    private

    def validate_scope!(scope)
      result = @scope_contract.call(scope:)
      raise InvalidReference, "project scope is invalid" if result.failure?
    end
  end
end
