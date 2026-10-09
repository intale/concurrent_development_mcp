# frozen_string_literal: true

module Coordinator::Read
  module Candidates
    class SubmissionLoader
      FACT_TYPES = %w[
        CandidateCreated
        CandidateAssignedToAttempt
        CandidateAssignedToRepository
        CandidateTargetBranchSelected
        CandidateCommitRangeDeclared
        CandidateCheckpointKindSelected
        CandidateWorkIntentionSetAssigned
        CandidateChangeManifestCaptured
        CandidateBuildContextCaptured
        CandidateSubmitted
      ].freeze

      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        instruction_loader: CommandResults::InstructionLoader.new(event_store:),
        target_command_builder: Coordinator::Write::Tasks::TargetCommandBuilder.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @instruction_loader = instruction_loader
        @target_command_builder = target_command_builder
      end

      def call(candidate_id)
        events = @event_store.read(
          @stream_factory.candidate(candidate_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: FACT_TYPES,
            maximum_count: 10,
            direction: :asc
          )
        )
        facts = events.to_h { |event| [ event.type, [ load_event(event), event ] ] }
        created, created_event = fetch_fact(facts, "CandidateCreated")
        attempt, = fetch_fact(facts, "CandidateAssignedToAttempt")
        repository, = fetch_fact(facts, "CandidateAssignedToRepository")
        branch, = fetch_fact(facts, "CandidateTargetBranchSelected")
        commit_range, = fetch_fact(facts, "CandidateCommitRangeDeclared")
        checkpoint, = fetch_fact(facts, "CandidateCheckpointKindSelected")
        intention_set, = fetch_fact(facts, "CandidateWorkIntentionSetAssigned")
        manifest, manifest_event = fetch_fact(facts, "CandidateChangeManifestCaptured")
        submitted, submitted_event = fetch_fact(facts, "CandidateSubmitted")
        build_context, build_context_event = facts["CandidateBuildContextCaptured"]

        identities = [
          created, attempt, repository, branch, commit_range, checkpoint,
          intention_set, manifest, build_context, submitted
        ].compact.map(&:candidate_id)
        unless identities.all? { _1 == candidate_id }
          raise InvalidProjectionSource, "Candidate facts disagree on candidate_id"
        end

        command = load_command(created_event)
        consistent = command.candidate_id == candidate_id &&
          command.change_set_id == attempt.change_set_id && command.work_item_id == attempt.work_item_id &&
          command.attempt_id == attempt.attempt_id && command.repository_id == repository.repository_id &&
          command.intention_set_id == intention_set.intention_set_id && command.target_branch == branch.target_branch &&
          command.object_format == commit_range.object_format && command.base_commit_oid == commit_range.base_commit_oid &&
          command.head_commit_oid == commit_range.head_commit_oid && command.checkpoint_kind == checkpoint.checkpoint_kind &&
          command.actor.id == created_event.metadata.fetch("actor_id") &&
          command.actor.kind == created_event.metadata.fetch("actor_kind") &&
          events.all? { _1.metadata.fetch("command_id") == command.command_id }
        raise InvalidProjectionSource, "Candidate facts do not match their submitting instruction" unless consistent

        CandidateSubmissionViewV2.new(
          candidate_id:,
          change_set_id: attempt.change_set_id,
          work_item_id: attempt.work_item_id,
          attempt_id: attempt.attempt_id,
          agent_id: created_event.metadata.fetch("actor_id"),
          repository_id: repository.repository_id,
          target_branch: branch.target_branch,
          object_format: commit_range.object_format,
          base_commit_oid: commit_range.base_commit_oid,
          head_commit_oid: commit_range.head_commit_oid,
          checkpoint_kind: checkpoint.checkpoint_kind,
          intention_set_id: intention_set.intention_set_id,
          intentions: load_intention_references(command),
          manifest_digest: manifest_event.metadata.fetch("manifest_digest"),
          build_context_digest: build_context_event&.metadata&.fetch("build_context_digest"),
          evidence_status: "attributed_unverified",
          manifest:,
          build_context:,
          submitted_event:,
          manifest_event:,
          build_context_event:
        )
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def fetch_fact(facts, type)
        facts.fetch(type) { raise InvalidProjectionSource, "Candidate is missing #{type}" }
      end

      def load_command(created_event)
        command_id = created_event.metadata.fetch("command_id")
        registration = @event_store.read(
          @stream_factory.command(command_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ "CommandRegistered" ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        raise InvalidProjectionSource, "Candidate submitting command is not registered" unless registration

        instruction = @instruction_loader.for_registration(registration)
        unless instruction&.tool_name == "candidate_submit"
          raise InvalidProjectionSource, "Candidate command has no matching submission instruction"
        end

        @target_command_builder.call(instruction)
      end

      def load_intention_references(command)
        command.intentions.map do |reference|
          declaration = load_first(
            @stream_factory.resource_work_intention(reference.intention_id),
            "ResourceWorkIntentionDeclared"
          )
          registration = load_first(
            @stream_factory.resource(reference.resource_id),
            "ResourceRegistered"
          )
          unless declaration.intention_id == reference.intention_id && declaration.resource_id == reference.resource_id &&
                 declaration.set_id == command.intention_set_id && declaration.fencing_token == reference.fencing_token &&
                 declaration.repository_id == command.repository_id && registration.repository_id == command.repository_id &&
                 declaration.change_set_id == command.change_set_id && declaration.work_item_id == command.work_item_id &&
                 declaration.attempt_id == command.attempt_id && declaration.agent_id == command.actor.id &&
                 registration.resource_id == reference.resource_id
            raise InvalidProjectionSource, "Candidate command-time work-intention reference is inconsistent"
          end

          WorkIntentionViewV1.new(
            intention_id: declaration.intention_id,
            resource_id: declaration.resource_id,
            resource_kind: registration.kind,
            resource_path: registration.normalized_path,
            base_blob_oid: declaration.base_blob_oid,
            mode: declaration.mode,
            purpose: declaration.purpose,
            context: declaration.context,
            fencing_token: declaration.fencing_token
          )
        end.sort_by { _1.resource_id.b }
      end

      def load_first(stream, event_type)
        event = @event_store.read(
          stream,
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ event_type ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        raise InvalidProjectionSource, "Candidate evidence is missing #{event_type}" unless event

        load_event(event)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
