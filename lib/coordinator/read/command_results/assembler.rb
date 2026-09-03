# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class Assembler
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        completion_builder: Coordinator::Write::CommandResultBuilder.new,
        semantic_result_mapper: Coordinator::Write::Tasks::SemanticResultMapper.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        stream_factory: Coordinator::Write::StreamFactory.new,
        repository_natural_key_marker: Coordinator::Write::Repositories::NaturalKeyMarker.new,
        development_artifact_marker_builder: Coordinator::Write::DevelopmentArtifacts::MarkerBuilder.new
      )
        @event_store = event_store
        @completion_builder = completion_builder
        @semantic_result_mapper = semantic_result_mapper
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @repository_natural_key_marker = repository_natural_key_marker
        @development_artifact_marker_builder = development_artifact_marker_builder
      end

      def call(source)
        semantic_result = if source.command_state.rejected?
                            rejected(source)
                          else
                            completion = successful_completion(source)
                            @semantic_result_mapper.call(
                              Success(completion),
                              command_id: source.command_state.request_id,
                              tool_name: source.command_state.tool_name
                            )
                          end

        ResultV1.from_semantic(
          semantic_result:,
          tool_name: source.command_state.tool_name,
          canonical_input_digest: source.command_state.canonical_input_digest,
          emitted_events: source.persisted_events.map { event_reference(_1) },
          completed_at: source.completed_at
        )
      end

      private

      def successful_completion(source)
        args = common_args(source)
        completion = case source.command_state.tool_name
        when "repository_register" then repository_registration(source)
        when "resource_resolve" then resource_resolution(source)
        when "resource_remove" then resource_removal(source)
        when "change_set_create" then @completion_builder.create_change_set(**args)
        when "work_item_create" then @completion_builder.work_item_create(**args)
        when "work_item_dependency_declare" then @completion_builder.work_item_dependency_declare(**args)
        when "change_set_activate" then @completion_builder.change_set_activate(**args)
        when "work_item_acquire" then @completion_builder.work_item_acquire(**args)
        when "work_item_complete"
          @completion_builder.work_item_complete(
            **args,
            completion: payload!(source, Coordinator::Write::Events::WorkItemCompletedV1)
          )
        when "attempt_abandon" then abandonment_completion(source)
        when "write_set_reserve"
          @completion_builder.write_set_reserve(
            **args,
            reservation: payload!(source, Coordinator::Write::Events::WriteSetReservedV2)
          )
        when "write_set_expand"
          @completion_builder.write_set_expand(
            **args,
            expansion: payload!(source, Coordinator::Write::Events::WriteSetExpandedV2)
          )
        when "lease_renew"
          @completion_builder.lease_renew(
            **args,
            renewal: payload!(source, Coordinator::Write::Events::WriteSetRenewedV2)
          )
        when "lease_release"
          @completion_builder.lease_release(
            **args,
            release: payload!(source, Coordinator::Write::Events::WriteSetReleasedV2)
          )
        when "guidance_record" then @completion_builder.guidance_record(**args)
        when "decision_interpretation_propose"
          @completion_builder.decision_interpretation_propose(
            **args,
            proposal: payload!(source, Coordinator::Write::Events::DecisionInterpretationProposedV1)
          )
        when "decision_interpretation_adjudicate"
          @completion_builder.decision_interpretation_adjudicate(
            **args,
            slot: payload(source, Coordinator::Write::Events::DecisionInterpretationAcceptedV1)&.slot
          )
        when "decision_activate" then decision_activation(source, args:)
        when "decision_correct" then decision_correction(source, args:)
        when "agent_choice_record"
          @completion_builder.agent_choice_record(
            **args,
            acceptance: payload!(source, Coordinator::Write::Events::AgentChoiceAcceptedV1)
          )
        when "candidate_submit"
          @completion_builder.candidate_submit(
            **args,
            submission: payload!(source, Coordinator::Write::Events::CandidateSubmittedV2)
          )
        when "candidate_impact_surface_submit"
          @completion_builder.candidate_impact_surface_submit(
            **args,
            surface: payload!(source, Coordinator::Write::Events::CandidateImpactSurfaceDerivedV1)
          )
        when "verification_obligation_claim"
          @completion_builder.verification_obligation_claim(
            **args,
            claim: payload!(source, Coordinator::Write::Events::VerificationObligationClaimedV1)
          )
        when "compatibility_assessment_submit"
          evidence = payload!(source, Coordinator::Write::Events::VerificationEvidenceSubmittedV1)
          @completion_builder.compatibility_assessment_submit(
            **args,
            evidence:,
            assessment_input_digest: evidence.assessment_input_digest
          )
        when "verification_obligation_waive"
          @completion_builder.verification_obligation_waive(
            **args,
            waiver: payload!(source, Coordinator::Write::Events::VerificationObligationWaivedV1)
          )
        when "merge_snapshot_register"
          @completion_builder.merge_snapshot_register(
            **args,
            snapshot: payload!(source, Coordinator::Write::Events::MergeSnapshotRegisteredV1)
          )
        when "merge_verification_submit"
          @completion_builder.merge_verification_submit(
            **args,
            submission: payload!(source, Coordinator::Write::Events::MergeSnapshotVerificationSubmittedV1)
          )
        when "merge_authorization_request"
          @completion_builder.merge_authorization_request(
            **args,
            decision: payloads(source).find do |candidate|
              candidate.is_a?(Coordinator::Write::Events::MergeAuthorizationGrantedV1) ||
                candidate.is_a?(Coordinator::Write::Events::MergeAuthorizationDeniedV1)
            end || missing_payload!(source, "merge authorization decision")
          )
        when "merge_observation_record"
          @completion_builder.merge_observation_record(
            **args,
            observation: payload!(source, Coordinator::Write::Events::MergeObservedV1)
          )
        when "release_set_prepare"
          @completion_builder.release_set_prepare(
            **args,
            preparation: payload!(source, Coordinator::Write::Events::ReleaseSetPreparedV1)
          )
        when "release_repository_integration_record"
          @completion_builder.release_repository_integration_record(
            **args,
            integration: payload!(source, Coordinator::Write::Events::RepositoryIntegrationRecordedV1)
          )
        when "release_verification_record"
          @completion_builder.release_verification_record(
            **args,
            verification: payload!(source, Coordinator::Write::Events::ReleaseSetVerificationRecordedV1)
          )
        when "release_activation_record"
          @completion_builder.release_activation_record(
            **args,
            activation: payload!(source, Coordinator::Write::Events::ReleaseSetActivatedV1)
          )
        when "release_compensation_complete"
          @completion_builder.release_compensation_complete(
            **args,
            completion: payload!(source, Coordinator::Write::Events::ReleaseSetCompletedV1)
          )
        when "skill_publish" then skill_publication(source, args:)
        when "development_artifact_capture" then development_artifact_capture(source, args:)
        when "development_artifact_classification_correct"
          development_artifact_classification(source, args:)
        when "development_artifact_relation_declare"
          development_artifact_relation(source, args:)
        when "skill_publish_batch", "development_artifact_capture_batch", "development_artifact_relation_declare_batch"
          @completion_builder.operation_batch_create(**args)
        when "operation_batch_cancel" then @completion_builder.operation_batch_cancel(**args)
        else
          raise InvalidProjectionSource,
                "No command-result projection exists for #{source.command_state.tool_name.inspect}"
        end

        request_id = source.command_state.request_id
        CompletionV1.new(
          completion.to_h.merge(
            command_id: request_id,
            receipt: request_id
          )
        )
      end

      def common_args(source)
        {
          command: source.command,
          input_digest: source.command_state.canonical_input_digest,
          persisted_events: source.persisted_events,
          completed_at: source.completed_at
        }
      end

      def rejected(source)
        attributes = source.terminal_event.metadata["rejection"]
        raise InvalidProjectionSource, "CommandRejected has no typed rejection evidence" unless attributes

        error = Coordinator::Write::Tasks::DomainErrorV1::Type[deep_symbolize(attributes)]
        @semantic_result_mapper.call(
          Failure(
            Coordinator::Write::OutcomeError.new(
              code: error.code.to_sym,
              message: error.message,
              details: error.details.to_h
            )
          ),
          command_id: source.command_state.request_id,
          tool_name: source.command_state.tool_name
        )
      end

      def decision_activation(source, args:)
        activation = payload!(source, Coordinator::Write::Events::DecisionActivatedV1)
        @completion_builder.decision_activate(
          **args,
          activation:,
          partitions: partition_receipts(source)
        )
      end

      def decision_correction(source, args:)
        correction = payload!(source, Coordinator::Write::Events::DecisionDefinitionCorrectedV1)
        @completion_builder.decision_correct(
          **args,
          correction:,
          correction_event: event_reference(event_for_payload(source, correction)),
          partitions: partition_receipts(source)
        )
      end

      def partition_receipts(source)
        payloads(source).filter_map.with_index do |candidate, index|
          next unless candidate.is_a?(Coordinator::Write::Events::DecisionPartitionAdvancedV1)

          Coordinator::Write::Decisions::DecisionPartitionReceiptV1.new(
            partition: candidate.partition,
            partition_revision: source.persisted_events.fetch(index).stream_revision
          )
        end
      end

      def skill_publication(source, args:)
        publication = payload(source, Coordinator::Write::Events::SkillRevisionPublishedV2)
        unless publication
          publication = load_first(
            @stream_factory.skill(source.command.skill_id),
            Coordinator::Write::EventQueries::SKILL_LATEST_REVISION
          )
        end
        @completion_builder.skill_publish(**args, publication:)
      end

      def development_artifact_capture(source, args:)
        command = source.command
        observation = payload(source, Coordinator::Write::Events::DevelopmentArtifactObservedV1) ||
                      load_observation(command.observation.observation_id).observation
        capture = payload(source, Coordinator::Write::Events::DevelopmentArtifactCapturedV2) ||
                  load_first(
                    @stream_factory.development_artifact(observation.observation.artifact_id),
                    Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_CAPTURE
                  )
        outcome = if payload(source, Coordinator::Write::Events::DevelopmentArtifactCapturedV2)
                    "captured"
                  elsif payload(source, Coordinator::Write::Events::DevelopmentArtifactObservedV1)
                    "observed"
                  else
                    "existing"
                  end
        artifact = capture.artifact
        observed = observation.observation
        completion(
          source,
          summary: {
            "captured" => "Development Artifact content and observation captured.",
            "observed" => "Development Artifact observation captured for existing content.",
            "existing" => "Development Artifact observation already exists."
          }.fetch(outcome),
          data: Coordinator::Write::CommandReceiptData::DevelopmentArtifactCapture.new(
            artifact_id: artifact.artifact_id,
            observation_id: observed.observation_id,
            classification_revision: 1,
            scope: observed.scope,
            kind: observed.kind,
            content_sha256: artifact.content.content_sha256,
            byte_size: artifact.content.byte_size,
            outcome:,
            recorded_at: observation.recorded_at
          ),
          next_actions: [
            Coordinator::Write::NextAction.new(
              tool: "development_artifact_get",
              arguments: Coordinator::Write::NextAction::DevelopmentArtifactArguments.new(
                artifact_id: artifact.artifact_id,
                observation_id: observed.observation_id
              )
            )
          ]
        )
      end

      def development_artifact_classification(source, args:)
        state = load_observation(source.command.observation_id)
        correction = payload(source, Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectedV1)
        outcome = correction ? "corrected" : "existing"
        completion(
          source,
          summary: outcome == "corrected" ?
            "Development Artifact observation classification corrected." :
            "Development Artifact observation classification is already current.",
          data: Coordinator::Write::CommandReceiptData::DevelopmentArtifactClassification.new(
            artifact_id: state.observation.observation.artifact_id,
            observation_id: source.command.observation_id,
            classification_revision: state.classification_revision,
            title: state.title,
            kind: state.kind,
            labels: state.labels,
            outcome:,
            corrected_at: source.completed_at
          ),
          next_actions: [
            Coordinator::Write::NextAction.new(
              tool: "development_artifact_get",
              arguments: Coordinator::Write::NextAction::DevelopmentArtifactArguments.new(
                artifact_id: state.observation.observation.artifact_id,
                observation_id: source.command.observation_id
              )
            )
          ]
        )
      end

      def development_artifact_relation(source, args:)
        command = source.command
        declaration = payload(source, Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV1) ||
                      load_artifact_relation(command)
        supersession = payload(source, Coordinator::Write::Events::DevelopmentArtifactRelationSupersededV1)
        outcome = if supersession
                    "superseded"
                  elsif source.persisted_events.empty?
                    "existing"
                  else
                    "declared"
                  end
        artifact_relation = declaration.artifact_relation
        completion(
          source,
          summary: {
            "declared" => "Development Artifact relation declared.",
            "superseded" => "Development Artifact relation superseded.",
            "existing" => "Development Artifact relation already exists."
          }.fetch(outcome),
          data: Coordinator::Write::CommandReceiptData::DevelopmentArtifactRelation.new(
            relation_id: artifact_relation.relation_id,
            source_artifact_id: artifact_relation.source_artifact_id,
            relation: artifact_relation.relation,
            target: artifact_relation.target,
            superseded_relation_id: supersession&.superseded_relation_id,
            outcome:,
            declared_at: declaration.declared_at,
            superseded_at: supersession&.superseded_at
          ),
          next_actions: [
            Coordinator::Write::NextAction.new(
              tool: "development_artifact_get",
              arguments: Coordinator::Write::NextAction::DevelopmentArtifactArguments.new(
                artifact_id: artifact_relation.source_artifact_id
              )
            )
          ]
        )
      end

      def repository_registration(source)
        registration = payload(source, Coordinator::Write::Events::RepositoryRegisteredV1) ||
                       load_repository_registration(source.command)
        outcome = source.persisted_events.empty? ? "existing" : "registered"
        completion(
          source,
          summary: outcome == "registered" ?
            "Repository registered under its exact coordination scope and key." :
            "Canonical Repository registration already exists for the exact scope and key.",
          data: Coordinator::Write::CommandReceiptData::RepositoryRegistration.new(
            repository_id: registration.repository_id,
            scope: registration.scope,
            display_name: registration.display_name,
            paths: registration.paths,
            remotes: registration.remotes,
            registered_at: registration.registered_at
          )
        )
      end

      def resource_resolution(source)
        command = source.command
        registration = payload(source, Coordinator::Write::Events::ResourceIdentityV1::Registered)
        binding = payload(source, Coordinator::Write::Events::ResourceIdentityV1::Bound)
        outcome = if registration
                    "registered"
                  elsif binding
                    "reactivated"
                  else
                    "existing"
                  end
        binding ||= current_resource_binding(command.identity.current_path_marker)
        registration ||= resource_registration(binding.resource_id)
        summary = {
          "registered" => "Resource identity registered and bound.",
          "reactivated" => "Existing Resource identity reactivated.",
          "existing" => "Existing Resource identity resolved."
        }.fetch(outcome)
        completion(
          source,
          summary:,
          data: Coordinator::Write::CommandReceiptData::ResourceResolution.new(
            resource_id: registration.resource_id,
            repository_id: registration.repository_id,
            kind: registration.kind,
            normalized_path: registration.normalized_path,
            outcome:,
            registered_at: registration.registered_at,
            bound_at: binding.bound_at
          )
        )
      end

      def resource_removal(source)
        command = source.command
        registration = resource_registration(command.resource_id)
        unbinding = payload(source, Coordinator::Write::Events::ResourceIdentityV1::Unbound)
        outcome = unbinding ? "removed" : "already_inactive"
        completion(
          source,
          summary: unbinding ? "Resource binding removed." : "Resource binding was already inactive.",
          data: Coordinator::Write::CommandReceiptData::ResourceRemoval.new(
            resource_id: registration.resource_id,
            repository_id: registration.repository_id,
            kind: registration.kind,
            normalized_path: registration.normalized_path,
            outcome:,
            reason: command.reason,
            unbound_at: unbinding&.unbound_at || source.completed_at
          )
        )
      end

      def abandonment_completion(source)
        abandonment = payload!(source, Coordinator::Write::Events::AttemptAbandonedV2)
        released_count = abandonment.released_leases.length
        untouched_count = abandonment.untouched_resource_ids.length
        warnings = [ "Reacquire the WorkItem with a fresh Attempt ID and base snapshot before resuming." ]
        if untouched_count.positive?
          warnings << "#{untouched_count} recorded lease fence(s) were already inactive or superseded and were left untouched."
        end
        completion(
          source,
          summary: "Attempt abandoned; WorkItem requeued; #{released_count} current lease fence(s) released.",
          data: Coordinator::Write::CommandReceiptData::Attempt.new(
            change_set_id: source.command.change_set_id,
            work_item_id: source.command.work_item_id,
            attempt_id: source.command.attempt_id
          ),
          warnings:
        )
      end

      def completion(source, summary:, data:, warnings: [], next_actions: [])
        CompletionV1.new(
          command_id: source.command_state.request_id,
          tool_name: source.command_state.tool_name,
          canonical_input_digest: source.command_state.canonical_input_digest,
          status: "ok",
          summary:,
          receipt: source.command_state.request_id,
          data:,
          warnings:,
          next_actions:,
          emitted_events: source.persisted_events.map { event_reference(_1) },
          completed_at: source.completed_at
        )
      end

      def payload(source, payload_class)
        source.payloads.find { _1.is_a?(payload_class) }
      end

      def payloads(source)
        source.payloads
      end

      def payload!(source, payload_class)
        payload(source, payload_class) || missing_payload!(source, payload_class.name)
      end

      def missing_payload!(source, description)
        raise InvalidProjectionSource,
              "#{source.command_state.tool_name} is missing #{description} projection evidence"
      end

      def event_for_payload(source, payload)
        index = source.payloads.index(payload)
        source.persisted_events.fetch(index)
      end

      def partition_payload?(payload)
        payload.is_a?(Coordinator::Write::Events::DecisionPartitionAdvancedV1)
      end

      def event_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def load_first(stream, criteria)
        event = @event_store.read(stream, criteria).first
        raise InvalidProjectionSource, "Required command-result source event does not exist" unless event

        load_payload(event)
      end

      def load_observation(observation_id)
        events = @event_store.read(
          @stream_factory.development_artifact_observation(observation_id),
          Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_OBSERVATION_HISTORY
        )
        ArtifactObservationState.reduce(events.map { load_payload(_1) })
      end

      def load_artifact_relation(command)
        marker = @development_artifact_marker_builder.relation_natural_key(command.artifact_relation)
        event = @event_store.read_global_marked(
          Coordinator::Write::GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentMemory",
            stream_name: "DevelopmentArtifact",
            event_types: [ "DevelopmentArtifactRelationDeclared" ],
            markers: [ marker ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        raise InvalidProjectionSource, "Development Artifact relation source does not exist" unless event

        load_payload(event)
      end

      def current_resource_binding(marker)
        event = @event_store.read_global_marked(
          Coordinator::Write::GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentCoordination",
            stream_name: "Resource",
            event_types: [ "ResourceBound" ],
            markers: [ marker ],
            maximum_count: 1,
            direction: :desc
          )
        ).first
        raise InvalidProjectionSource, "Resolved Resource binding does not exist" unless event

        load_payload(event)
      end

      def resource_registration(resource_id)
        load_first(
          @stream_factory.resource(resource_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ "ResourceRegistered" ],
            maximum_count: 1,
            direction: :asc
          )
        )
      end

      def load_repository_registration(command)
        marker = @repository_natural_key_marker.call(
          scope: command.scope,
          repository_key: command.repository_key
        )
        event = @event_store.read_global_marked(
          Coordinator::Write::GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentPlanning",
            stream_name: "Repository",
            event_types: [ "RepositoryRegistered" ],
            markers: [ marker.marker ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        raise InvalidProjectionSource, "Canonical Repository registration does not exist" unless event

        load_payload(event)
      end

      def load_payload(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def deep_symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, deep_symbolize(nested) ] }
        when Array then value.map { deep_symbolize(_1) }
        else value
        end
      end
    end
  end
end
