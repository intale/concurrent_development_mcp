# frozen_string_literal: true

module RepositoryAcceptance
  DEFAULT_REPOSITORY_ID = "01a03deb-6f55-74ba-bcc0-afd02e7b14dc"
  DEFAULT_SCOPE = "project:test/billing"

  def acceptance_repository_id(key = "billing")
    value = key.to_s
    return value if Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
    return DEFAULT_REPOSITORY_ID if value == "billing"

    digest = Coordinator::Shared::CanonicalJson.new.sha256(
      { "test_repository" => value }
    ).delete_prefix("sha256:")
    "01a03deb-#{digest[0, 4]}-7#{digest[4, 3]}-8#{digest[7, 3]}-#{digest[10, 12]}"
  end

  def acceptance_repository_scope(key = "billing")
    value = key.to_s
    return DEFAULT_SCOPE if value == "billing" || value == DEFAULT_REPOSITORY_ID

    "project:test/#{value}"
  end

  def register_acceptance_repository(key = "billing")
    repository_id = acceptance_repository_id(key)
    return repository_id if registered_acceptance_repositories.include?(repository_id)

    result = Coordinator::Write::Operations::ExecuteRegisterRepository.new(
      event_store: Coordinator::Write::EventStore.new(client: PgEventstore.client)
    ).call(
      command_id: "seed-register-#{repository_id}",
      actor: { kind: "agent", id: "test-repository-registrar" },
      repository_id:,
      scope: acceptance_repository_scope(key),
      display_name: "#{key.to_s.capitalize} test repository",
      paths: [],
      remotes: []
    )
    result.value!
    registered_acceptance_repositories << repository_id
    repository_id
  end

  def reset_acceptance_repositories!
    @registered_acceptance_repositories = []
  end

  private

  def registered_acceptance_repositories
    @registered_acceptance_repositories ||= []
  end
end

World(RepositoryAcceptance)
