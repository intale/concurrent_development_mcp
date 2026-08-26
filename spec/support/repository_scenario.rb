# frozen_string_literal: true

module RepositoryScenario
  DEFAULT_REPOSITORY_ID = "01a03deb-6f55-74ba-bcc0-afd02e7b14dc"
  DEFAULT_SCOPE = "project:test/billing"

  module_function

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
    repository_id: DEFAULT_REPOSITORY_ID,
    scope: DEFAULT_SCOPE,
    display_name: "Billing test repository"
  )
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
