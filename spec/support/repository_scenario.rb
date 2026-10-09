# frozen_string_literal: true

module RepositoryScenario
  DEFAULT_REPOSITORY_ID = "01a03deb-6f55-74ba-bcc0-afd02e7b14dc"
  DEFAULT_SCOPE = "project:test/billing"

  module_function

  @repository_ids_mutex = Thread::Mutex.new

  def repository_id(key = "billing")
    value = key.to_s
    return value if Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
    return DEFAULT_REPOSITORY_ID if value == "billing"

    @repository_ids_mutex.synchronize do
      @repository_ids ||= {}
      @repository_ids[value] ||= SecureRandom.uuid_v7
    end
  end

  def scope(key = "billing")
    value = key.to_s
    return DEFAULT_SCOPE if value == "billing" || value == DEFAULT_REPOSITORY_ID

    "project:test/#{value}"
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
      repository_key: key.to_s,
      display_name:,
      paths: [],
      remotes: []
    )

    result.value!
    repository_id
  end
end
