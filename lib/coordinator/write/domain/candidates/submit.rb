# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Candidates
      class Submit
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, submitted_at:, head_identity:)
          denial = denied(state:, command:, submitted_at:)
          return denial if denial

          Success(build_plan(command:, state:, head_identity:))
        end

        private

        def denied(state:, command:, submitted_at:)
          if state.existing_candidate
            return failure(
              :candidate_id_already_used,
              "Candidate ID already has an immutable submission",
              candidate_id: command.candidate_id,
              existing_event: state.existing_candidate.to_h
            )
          end
          if state.existing_head
            return failure(
              :candidate_head_already_registered,
              "Repository head already belongs to another Candidate",
              candidate_id: command.candidate_id,
              repository_id: command.repository_id,
              object_format: command.object_format,
              head_commit_oid: command.head_commit_oid,
              existing_event: state.existing_head.to_h
            )
          end

          attempt_denial = denied_attempt(state.attempt, command)
          return attempt_denial if attempt_denial

          write_set_denial = denied_write_set(state, command, submitted_at:)
          return write_set_denial if write_set_denial

          denied_manifest_resources(state.attempt, command)
        end

        def denied_attempt(attempt, command)
          return scoped_failure(:attempt_not_found, "Attempt does not exist", command) if attempt.absent?
          return scoped_failure(:attempt_not_active, "Attempt is not active", command) unless attempt.status == "active"
          unless attempt.attempt_id == command.attempt_id &&
                 attempt.change_set_id == command.change_set_id &&
                 attempt.work_item_id == command.work_item_id
            return scoped_failure(:attempt_scope_mismatch, "Attempt does not belong to the requested scope", command)
          end
          unless attempt.agent_id == command.actor.id
            return scoped_failure(:attempt_actor_mismatch, "Attempt belongs to another agent attribution", command)
          end

          snapshot = attempt.base_snapshots.first
          return scoped_failure(:repository_base_mismatch, "Attempt has no repository base", command) unless snapshot
          return if snapshot.repository_id == command.repository_id &&
                    snapshot.object_format == command.object_format &&
                    snapshot.commit_oid == command.base_commit_oid

          scoped_failure(:repository_base_mismatch, "Repository base does not match the Attempt", command)
        end

        def denied_write_set(state, command, submitted_at:)
          attempt = state.attempt
          return scoped_failure(:write_set_not_reserved, "Attempt has no reserved write set", command) unless attempt.lease_set_id
          if attempt.lease_released_at
            return failure(
              :lease_set_released,
              "Attempt write set has been released",
              change_set_id: command.change_set_id,
              work_item_id: command.work_item_id,
              attempt_id: command.attempt_id,
              released_at: attempt.lease_released_at
            )
          end
          unless attempt.lease_set_id == command.lease_set_id &&
                 attempt.lease_repository_id == command.repository_id &&
                 attempt.lease_policy_version == LeaseResourceV2::POLICY_VERSION
            return failure(
              :lease_set_mismatch,
              "Lease set does not match the Attempt",
              change_set_id: command.change_set_id,
              work_item_id: command.work_item_id,
              attempt_id: command.attempt_id,
              current_lease_set_id: attempt.lease_set_id,
              requested_lease_set_id: command.lease_set_id
            )
          end

          expected = attempt.lease_resources.map { [ _1.resource_id, _1.lease_id, _1.fencing_token ] }
          submitted = command.leases.map { [ _1.resource_id, _1.lease_id, _1.fencing_token ] }
          unless submitted == expected
            return failure(
              :lease_observations_mismatch,
              "Submitted lease observations are not the exact Attempt lease set",
              attempt_id: command.attempt_id,
              expected_resource_ids: expected.map(&:first),
              submitted_resource_ids: submitted.map(&:first)
            )
          end

          observed_references = state.current_leases.map(&:reference)
          unless observed_references == attempt.lease_resources
            return scoped_failure(
              :lease_not_active,
              "Current lease evidence is incomplete for the Attempt write set",
              command
            )
          end

          invalid = state.current_leases.find { !current_lease?(_1, state.attempt, command, submitted_at:) }
          return unless invalid

          failure(
            :lease_not_active,
            "A submitted lease observation is stale or inactive",
            attempt_id: command.attempt_id,
            resource_id: invalid.reference.resource_id,
            submitted_lease_id: invalid.reference.lease_id,
            current_lease_id: invalid.state.lease_id,
            current_fencing_token: invalid.state.fencing_token,
            expires_at: invalid.state.expires_at
          )
        end

        def current_lease?(observation, attempt, command, submitted_at:)
          reference = observation.reference
          state = observation.state
          state.active_at?(submitted_at) &&
            state.lease_id == reference.lease_id &&
            state.lease_set_id == command.lease_set_id &&
            state.resource_id == reference.resource_id &&
            state.fencing_token == reference.fencing_token &&
            state.change_set_id == command.change_set_id &&
            state.work_item_id == command.work_item_id &&
            state.attempt_id == command.attempt_id &&
            state.agent_id == command.actor.id &&
            state.repository_id == command.repository_id &&
            state.object_format == command.object_format &&
            state.base_commit_oid == command.base_commit_oid &&
            state.policy_version == attempt.lease_policy_version
        end

        def denied_manifest_resources(attempt, command)
          leased = attempt.lease_resources
          missing = command.actual_resources.reject { covering_lease(leased, _1) }
          unless missing.empty?
            return failure(
              :actual_write_set_not_authorized,
              "Candidate manifest includes resources outside the reserved write set",
              candidate_id: command.candidate_id,
              resources: missing.map { { path: _1.path } }
            )
          end

          mismatch = command.actual_resources.find do |resource|
            reference = leased.find do |candidate|
              candidate.resource_kind == "file" && candidate.resource_path == resource.path
            end
            reference && reference.base_blob_oid != resource.base_blob_oid
          end
          return unless mismatch

          reference = leased.find { _1.resource_kind == "file" && _1.resource_path == mismatch.path }
          failure(
            :manifest_base_evidence_mismatch,
            "Candidate manifest old-side evidence differs from the reserved base",
            candidate_id: command.candidate_id,
            resource_id: reference.resource_id,
            path: mismatch.path,
            expected_base_blob_oid: reference.base_blob_oid,
            submitted_base_blob_oid: mismatch.base_blob_oid
          )
        end

        def covering_lease(leased, resource)
          leased.find do |reference|
            (reference.resource_kind == "file" && reference.resource_path == resource.path) ||
              (reference.resource_kind == "directory" &&
                (resource.path == reference.resource_path ||
                  resource.path.start_with?("#{reference.resource_path}/")))
          end
        end

        def build_plan(command:, state:, head_identity:)
          candidate_stream = @stream_factory.candidate(command.candidate_id)
          manifest = command.manifest
          context = command.build_context
          writes = [
            EventWrite.new(
              stream: candidate_stream,
              event: Events::CandidateCreatedV1.new(candidate_id: command.candidate_id)
            ),
            EventWrite.new(
              stream: candidate_stream,
              event: Events::CandidateAssignedToAttemptV1.new(
                candidate_id: command.candidate_id,
                attempt_id: command.attempt_id,
                work_item_id: command.work_item_id,
                change_set_id: command.change_set_id
              )
            ),
            EventWrite.new(
              stream: candidate_stream,
              event: Events::CandidateAssignedToRepositoryV1.new(
                candidate_id: command.candidate_id,
                repository_id: command.repository_id
              )
            ),
            EventWrite.new(
              stream: candidate_stream,
              event: Events::CandidateTargetBranchSelectedV1.new(
                candidate_id: command.candidate_id,
                target_branch: command.target_branch
              )
            ),
            EventWrite.new(
              stream: candidate_stream,
              event: Events::CandidateCommitRangeDeclaredV1.new(
                candidate_id: command.candidate_id,
                object_format: command.object_format,
                base_commit_oid: command.base_commit_oid,
                head_commit_oid: command.head_commit_oid
              )
            ),
            EventWrite.new(
              stream: candidate_stream,
              event: Events::CandidateCheckpointKindSelectedV1.new(
                candidate_id: command.candidate_id,
                checkpoint_kind: command.checkpoint_kind
              )
            ),
            EventWrite.new(
              stream: candidate_stream,
              event: Events::CandidateWorkIntentionSetAssignedV1.new(
                candidate_id: command.candidate_id,
                intention_set_id: command.lease_set_id
              )
            ),
            EventWrite.new(
              stream: candidate_stream,
              event: Events::CandidateChangeManifestCapturedV2.new(
                candidate_id: command.candidate_id,
                evidence_revision: 1,
                files: manifest.files
              )
            )
          ]
          writes << build_context_write(command, context, candidate_stream) if context
          writes.concat([
            EventWrite.new(
              stream: candidate_stream,
              event: Events::CandidateSubmittedV3.new(candidate_id: command.candidate_id)
            ),
            EventWrite.new(
              stream: @stream_factory.candidate_head(head_identity.registry_id),
              event: Events::CandidateHeadRegisteredV2.new(
                registry_id: head_identity.registry_id,
                candidate_id: command.candidate_id,
                attempt_id: command.attempt_id,
                repository_id: command.repository_id,
                object_format: command.object_format,
                head_commit_oid: command.head_commit_oid
              )
            )
          ])
          EventPlan.new(writes:)
        end

        def build_context_write(command, context, candidate_stream)
          EventWrite.new(
            stream: candidate_stream,
            event: Events::CandidateBuildContextCapturedV2.new(
              candidate_id: command.candidate_id,
              evidence_revision: 1,
              inputs: context.inputs,
              environment: context.environment
            )
          )
        end

        def scoped_failure(code, message, command)
          failure(
            code,
            message,
            change_set_id: command.change_set_id,
            work_item_id: command.work_item_id,
            attempt_id: command.attempt_id
          )
        end

        def failure(code, message, **details)
          Failure(OutcomeError.new(code:, message:, details:))
        end
      end
    end
  end
end
