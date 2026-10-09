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

          intention_denial = denied_work_intentions(state, command, submitted_at:)
          return intention_denial if intention_denial

          denied_manifest_resources(state.current_intentions, command)
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

        def denied_work_intentions(state, command, submitted_at:)
          set = state.intention_set
          unless set && !set.absent?
            return scoped_failure(:work_intention_set_missing, "Attempt has no declared work-intention set", command)
          end
          unless set.set_id == command.intention_set_id && set.repository_id == command.repository_id &&
                 set.change_set_id == command.change_set_id && set.work_item_id == command.work_item_id &&
                 set.attempt_id == command.attempt_id
            return failure(
              :work_intention_set_mismatch,
              "Work-intention set does not match the Attempt",
              change_set_id: command.change_set_id,
              work_item_id: command.work_item_id,
              attempt_id: command.attempt_id,
              current_intention_set_id: set.set_id,
              requested_intention_set_id: command.intention_set_id
            )
          end

          expected = set.members
            .map { [ _1.resource_id, _1.intention_id ] }
            .sort_by { _1.first.b }
          submitted = command.intentions
            .map { [ _1.resource_id, _1.intention_id ] }
            .sort_by { _1.first.b }
          unless submitted == expected
            return failure(
              :work_intention_observations_mismatch,
              "Submitted intention observations are not the exact Attempt work-intention set",
              attempt_id: command.attempt_id,
              expected_resource_ids: expected.map(&:first),
              submitted_resource_ids: submitted.map(&:first)
            )
          end

          observed = state.current_intentions
            .map { [ _1.state.resource_id, _1.state.intention_id ] }
            .sort_by { _1.first.to_s.b }
          unless observed == expected
            return scoped_failure(
              :work_intention_not_active,
              "Current intention evidence is incomplete for the Attempt work-intention set",
              command
            )
          end

          fences = state.current_intentions.to_h { [ _1.state.resource_id, _1.state.fencing_token ] }
          unless command.intentions.all? { fences.fetch(_1.resource_id) == _1.fencing_token }
            return failure(
              :work_intention_observations_mismatch,
              "Submitted fencing evidence is not the current work-intention set",
              attempt_id: command.attempt_id,
              expected_resource_ids: expected.map(&:first),
              submitted_resource_ids: submitted.map(&:first)
            )
          end

          if state.current_intentions.all? { _1.state.withdrawn }
            return scoped_failure(:work_intention_set_withdrawn, "Attempt work-intention set has been withdrawn", command)
          end

          submitted_by_resource = command.intentions.to_h { [ _1.resource_id, _1 ] }
          invalid = state.current_intentions.find do |observation|
            reference = submitted_by_resource.fetch(observation.state.resource_id)
            !current_intention?(observation, reference, command, submitted_at:)
          end
          return unless invalid

          failure(
            :work_intention_not_active,
            "A submitted work-intention observation is stale or inactive",
            attempt_id: command.attempt_id,
            resource_id: invalid.state.resource_id,
            submitted_intention_id: submitted_by_resource.fetch(invalid.state.resource_id).intention_id,
            current_intention_id: invalid.state.intention_id,
            current_fencing_token: invalid.state.fencing_token,
            expires_at: invalid.state.expires_at
          )
        end

        def current_intention?(observation, reference, command, submitted_at:)
          state = observation.state
          resource = observation.resource
          state.active_at?(submitted_at) &&
            state.intention_id == reference.intention_id &&
            state.set_id == command.intention_set_id &&
            state.resource_id == reference.resource_id &&
            resource.resource_id == reference.resource_id &&
            state.fencing_token == reference.fencing_token &&
            state.change_set_id == command.change_set_id &&
            state.work_item_id == command.work_item_id &&
            state.attempt_id == command.attempt_id &&
            state.agent_id == command.actor.id &&
            state.repository_id == command.repository_id &&
            state.object_format == command.object_format &&
            state.base_commit_oid == command.base_commit_oid &&
            state.base_blob_oid == resource.base_blob_oid
        end

        def denied_manifest_resources(intentions, command)
          resources = intentions.map(&:resource)
          missing = command.actual_resources.reject { covering_intention(resources, _1) }
          unless missing.empty?
            return failure(
              :candidate_resources_not_covered,
              "Candidate manifest includes resources outside the declared work-intention set",
              candidate_id: command.candidate_id,
              resources: missing.map { { path: _1.path } }
            )
          end

          mismatch = command.actual_resources.find do |resource|
            reference = resources.find do |candidate|
              candidate.kind == "file" && candidate.path == resource.path
            end
            reference && reference.base_blob_oid != resource.base_blob_oid
          end
          return unless mismatch

          reference = resources.find { _1.kind == "file" && _1.path == mismatch.path }
          failure(
            :manifest_base_evidence_mismatch,
            "Candidate manifest old-side evidence differs from the declared base",
            candidate_id: command.candidate_id,
            resource_id: reference.resource_id,
            path: mismatch.path,
            expected_base_blob_oid: reference.base_blob_oid,
            submitted_base_blob_oid: mismatch.base_blob_oid
          )
        end

        def covering_intention(intentions, resource)
          intentions.find do |reference|
            (reference.kind == "file" && reference.path == resource.path) ||
              (reference.kind == "directory" &&
                (resource.path == reference.path || resource.path.start_with?("#{reference.path}/")))
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
                intention_set_id: command.intention_set_id
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
