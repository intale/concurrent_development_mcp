# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::SourceEventSchemaRegistry do
  subject(:registry) { described_class.new }

  it "owns exactly the frozen pre-remodel and post-remodel source schemas" do
    expected = [
      *Coordinator::Write::HistoryMigrations::LegacyContractCatalog::SOURCE_CONTRACTS,
      *Coordinator::Write::HistoryMigrations::PostRemodelContractCatalog::SOURCE_CONTRACTS
    ]

    expect(described_class::DEFINITIONS.keys).to match_array(expected)
    expect(expected.map { |type, schema_version| registry.fetch(type:, schema_version:) }).to all(
      be < Coordinator::Write::Events::Base
    )
  end

  it "loads both removed legacy payloads and post-remodel payloads" do
    legacy = registry.load(
      type: "CoordinationTaskExecutionStarted",
      schema_version: 1,
      data: {
        "task_id" => "018f0f4d-4e45-7abc-8def-000000000901",
        "started_at" => "2026-08-01T12:00:00.000000Z"
      }
    )
    current = registry.load(
      type: "AttemptAuthorized",
      schema_version: 2,
      data: { "attempt_id" => "018f0f4d-4e45-7abc-8def-000000000902" }
    )

    expect(legacy).to be_a(
      Coordinator::Write::HistoryMigrations::LegacyEvents::CoordinationTaskExecutionStartedV1
    )
    expect(current).to be_a(Coordinator::Write::Events::AttemptAuthorizedV2)
  end

  it "freezes payload shapes that changed while the post-remodel source range was live" do
    old_head = registry.load(
      type: "CandidateHeadRegistered",
      schema_version: 2,
      data: {
        "registry_id" => "018f0f4d-4e45-7abc-8def-000000000910",
        "candidate_id" => "source-candidate",
        "attempt_id" => "source-attempt",
        "repository_id" => "018f0f4d-4e45-7abc-8def-000000000911",
        "object_format" => "sha1",
        "head_commit_oid" => "a" * 40,
        "candidate_event" => {
          "event_id" => "018f0f4d-4e45-7abc-8def-000000000912",
          "type" => "CandidateSubmitted",
          "stream_context" => "DevelopmentIntegration",
          "stream_name" => "Candidate",
          "stream_id" => "source-candidate",
          "stream_revision" => 0
        },
        "registered_at" => "2026-09-02T18:08:34.846261Z"
      }
    )
    old_reservation = registry.load(
      type: "CoordinationTaskSubmitted",
      schema_version: 3,
      data: task_submission(
        tool_name: "write_set_reserve",
        input: {
          "actor" => { "actor_kind" => "agent", "actor_id" => "codex" },
          "change_set_id" => "source-change-set",
          "work_item_id" => "source-work-item",
          "attempt_id" => "source-attempt",
          "repository_id" => "018f0f4d-4e45-7abc-8def-000000000911",
          "base_commit_oid" => "b" * 40,
          "resources" => [
            {
              "resource_id" => "018f0f4d-4e45-7abc-8def-000000000913",
              "base_blob_oid" => nil
            }
          ],
          "lease_duration_seconds" => 3_600
        }
      )
    )
    intermediate_reservation = registry.load(
      type: "CoordinationTaskSubmitted",
      schema_version: 3,
      data: task_submission(
        tool_name: "write_set_reserve",
        input: {
          "actor" => { "actor_kind" => "agent", "actor_id" => "codex" },
          "change_set_id" => "source-change-set",
          "work_item_id" => "source-work-item",
          "attempt_id" => "source-attempt",
          "repository_id" => "018f0f4d-4e45-7abc-8def-000000000911",
          "base_commit_oid" => "b" * 40,
          "resources" => [
            {
              "resource_id" => "018f0f4d-4e45-7abc-8def-000000000913",
              "base_blob_oid" => nil,
              "mode" => "shared",
              "purpose" => "Review the source range",
              "context" => "Migration planning"
            }
          ],
          "lease_duration_seconds" => 3_600
        }
      )
    )

    expect(old_head).to be_a(
      Coordinator::Write::HistoryMigrations::PostRemodelEvents::CandidateHeadRegisteredV2
    )
    expect(old_reservation.command_input.input.resources.sole.mode).to be_nil
    expect(intermediate_reservation.command_input.input.resources.sole).to have_attributes(
      mode: "shared",
      purpose: "Review the source range",
      context: "Migration planning"
    )
  end

  def task_submission(tool_name:, input:)
    command_id = "018f0f4d-4e45-7abc-8def-000000000914"
    {
      "task_id" => "018f0f4d-4e45-7abc-8def-000000000915",
      "command_id" => command_id,
      "tool_name" => tool_name,
      "command_input" => {
        "schema" => "command-input/v1",
        "command_id" => command_id,
        "tool_name" => tool_name,
        "input" => input
      },
      "poll_interval_ms" => 500,
      "ttl_ms" => nil
    }
  end
end
