# frozen_string_literal: true

module DevelopmentSearchAcceptanceWorld
  def search_literal(value, match: "contains", **attributes)
    { match:, value:, **attributes }
  end

  def search_branch(field, expression)
    { field:, query: expression }
  end

  def search_response(fields, **options)
    call_tool("development_search", { fields:, **options })
  end

  def search_page(fields, **options)
    response = search_response(fields, **options)
    result = response.fetch("result")
    assert_acceptance(!result.key?("taskId"), "Search must be an immediate read, not a Task")
    payload = result.fetch("structuredContent")
    assert_acceptance_equal("ok", payload.fetch("status"), "Search status")
    assert_acceptance_equal(nil, payload.fetch("command_id"), "Search has no command")
    payload.fetch("data").fetch("page")
  end

  def publish_search_skill(name:, scope:, instructions:, assets: [], command_id:)
    publication = publish_skill_task(name:, scope:, instructions:, assets:, command_id:, expected_revision: 0)
    assert_acceptance_equal("ok", publication.fetch(:outcome).fetch("status"), "Search Skill publication")
    await_skill_revision(skill_events(name:, scope:).last)
    publication.fetch(:outcome).fetch("data").fetch("skill_id")
  end

  def search_artifact(index, text)
    labels = [ [ "bar middle baz", "evidence" ], [ "bar middle", "middle baz" ], [ "bar excluded baz" ] ].fetch(index)
    outcome = capture_artifact_task(command_id: "search-artifact-#{index}-#{@search_artifact_capture.to_i}",
      title: "checkpoint artifact #{index}", kind: "documentation", labels:,
      scope: acceptance_repository_scope, locator: "docs/search-#{index}.md", source_kind: "local_file",
      content: { encoding: "utf-8", media_type: "text/plain", text: })
    @search_artifact_capture = @search_artifact_capture.to_i + 1
    assert_acceptance_equal("ok", outcome.fetch("status"), "Search Artifact capture")
    data = outcome.fetch("data")
    await_read_model("Search Artifact content to reach its observation") do
      payload = artifact_content(data.fetch("artifact_id"), observation_id: data.fetch("observation_id"))
      [ payload.dig("data", "content", "text") == text, payload ]
    end
    data
  end

  def release_search_lock
    @search_lock_release << true if @search_lock_thread&.alive?
    @search_lock_thread&.value
    @search_lock_thread = nil
  end
end

World(DevelopmentSearchAcceptanceWorld)

After do
  release_search_lock
end
