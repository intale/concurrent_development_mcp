# frozen_string_literal: true

module RepositoryScenario
  DEFAULT_REPOSITORY_ID = "01a03deb-6f55-74ba-bcc0-afd02e7b14dc"
  DEFAULT_SCOPE = "project:test/billing"

  module_function

  def repository_id(key = "billing")
    value = key.to_s
    return value if Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
    return DEFAULT_REPOSITORY_ID if value == "billing"

    digest = Coordinator::Shared::CanonicalJson.new.sha256(
      { "test_repository" => value }
    ).delete_prefix("sha256:")
    "01a03deb-#{digest[0, 4]}-7#{digest[4, 3]}-8#{digest[7, 3]}-#{digest[10, 12]}"
  end

  def scope(key = "billing")
    value = key.to_s
    return DEFAULT_SCOPE if value == "billing" || value == DEFAULT_REPOSITORY_ID

    "project:test/#{value}"
  end

  def registration(
    repository_id: DEFAULT_REPOSITORY_ID,
    scope: DEFAULT_SCOPE,
    display_name: "Billing test repository"
  )
    Coordinator::Write::Events::RepositoryRegisteredV1.new(
      repository_id:,
      scope:,
      display_name:,
      paths: [],
      remotes: [],
      registered_at: "2026-08-26T00:00:00.000000Z"
    )
  end

  def register(
    event_store:,
    key: "billing",
    repository_id: repository_id(key),
    scope: scope(key),
    display_name: nil
  )
    display_name ||= "#{key.to_s.capitalize} test repository"
    result = Coordinator::Write::Operations::ExecuteRegisterRepository.new(event_store:).call(
      command_id: "seed-register-#{repository_id}",
      actor: { kind: "agent", id: "test-repository-registrar" },
      repository_id:,
      scope:,
      display_name:,
      paths: [],
      remotes: []
    )

    result.value!
    repository_id
  end
end
