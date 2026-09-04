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
        repository_registration_loader: Coordinator::Write::RepositoryRegistrationLoader.new(event_store:),
        repository_natural_key_marker: Coordinator::Write::Repositories::NaturalKeyMarker.new,
        development_artifact_marker_builder: Coordinator::Write::DevelopmentArtifacts::MarkerBuilder.new,
        release_set_preparation_loader: Coordinator::Read::ReleaseSets::PreparationLoader.new(event_store:),
        work_intention_set_evidence_loader: WorkIntentionSetEvidenceLoader.new(event_store:)
      )
        @event_store = event_store
        @completion_builder = completion_builder
        @semantic_result_mapper = semantic_result_mapper
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @repository_registration_loader = repository_registration_loader
        @repository_natural_key_marker = repository_natural_key_marker
        @development_artifact_marker_builder = development_artifact_marker_builder
        @release_set_preparation_loader = release_set_preparation_loader
        @work_intention_set_evidence_loader = work_intention_set_evidence_loader
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
          selection = payload!(source, Coordinator::Write::Events::WorkItemCandidateSelectedV2)
          @completion_builder.work_item_complete(
            **args,
            candidate_event: selection.candidate_event
          )
        when "attempt_abandon" then abandonment_completion(source)
        when "write_set_reserve" then write_set_reservation(source, args:)
        when "write_set_expand" then write_set_expansion(source, args:)
        when "lease_renew" then work_intention_set_renewal(source, args:)
        when "lease_release" then work_intention_set_release(source, args:)
        when "guidance_record" then @completion_builder.guidance_record(**args)
        when "decision_interpretation_propose"
          proposal = payload!(source, Coordinator::Write::Events::DecisionInterpretationProposedV2)
          @completion_builder.decision_interpretation_propose(
            **args,
            assessment: proposal.assessment
          )
        when "decision_interpretation_adjudicate"
          @completion_builder.decision_interpretation_adjudicate(
            **args,
            slot: payload(source, Coordinator::Write::Events::DecisionInterpretationAcceptedV2)&.slot
          )
        when "decision_activate" then decision_activation(source, args:)
        when "decision_correct" then decision_correction(source, args:)
        when "agent_choice_record"
          recorded = payload!(source, Coordinator::Write::Events::AgentChoiceRecordedV2)
          @completion_builder.agent_choice_record(
            **args,
            recorded:,
            acceptance: payload!(source, Coordinator::Write::Events::AgentChoiceAcceptedV2)
          )
        when "candidate_submit"
          @completion_builder.candidate_submit(**args)
        when "candidate_impact_surface_submit"
          surface = payload!(source, Coordinator::Write::Events::CandidateImpactSurfaceDerivedV2)
          @completion_builder.candidate_impact_surface_submit(
            **args,
            surface_id: surface.surface_id
          )
        when "verification_obligation_claim"
          @completion_builder.verification_obligation_claim(
            **args,
            claim: payload!(source, Coordinator::Write::Events::VerificationObligationClaimedV2)
          )
        when "compatibility_assessment_submit"
          evidence = payload!(source, Coordinator::Write::Events::VerificationEvidenceSubmittedV2)
          evidence_event = event_for_payload(source, evidence)
          @completion_builder.compatibility_assessment_submit(
            **args,
            evidence:,
            assessment_input_digest: evidence_event.metadata.fetch("assessment_input_digest")
          )
        when "verification_obligation_waive"
          @completion_builder.verification_obligation_waive(
            **args,
            waiver: payload!(source, Coordinator::Write::Events::VerificationObligationWaivedV2)
          )
        when "merge_snapshot_register"
          snapshot = payload!(source, Coordinator::Write::Events::MergeSnapshotRegisteredV2)
          snapshot_event = event_for_payload(source, snapshot)
          @completion_builder.merge_snapshot_register(
            **args,
            snapshot_digest: snapshot_event.metadata.fetch("snapshot_digest"),
            registered_at: snapshot_event.created_at.utc.iso8601(6)
          )
        when "merge_verification_submit"
          submission = payload!(source, Coordinator::Write::Events::MergeSnapshotVerificationSubmittedV2)
          submission_event = event_for_payload(source, submission)
          @completion_builder.merge_verification_submit(
            **args,
            submission:,
            verification_input_digest: submission_event.metadata.fetch("verification_input_digest")
          )
        when "merge_authorization_request"
          decision = payloads(source).find do |candidate|
            candidate.is_a?(Coordinator::Write::Events::MergeAuthorizationGrantedV2) ||
              candidate.is_a?(Coordinator::Write::Events::MergeAuthorizationDeniedV2)
          end || missing_payload!(source, "merge authorization decision")
          decision_event = event_for_payload(source, decision)
          @completion_builder.merge_authorization_request(
            **args,
            decision:,
            decision_digest: decision_event.metadata.fetch("decision_digest"),
            decided_at: decision_event.created_at.utc.iso8601(6)
          )
        when "merge_observation_record"
          observation = payload!(source, Coordinator::Write::Events::MergeObservedV2)
          observation_event = event_for_payload(source, observation)
          @completion_builder.merge_observation_record(
            **args,
            observation:,
            observation_digest: observation_event.metadata.fetch("observation_digest"),
            recorded_at: observation_event.created_at.utc.iso8601(6)
          )
        when "release_set_prepare"
          created = payload!(source, Coordinator::Write::Events::ReleaseSetCreatedV1)
          members = payloads(source).grep(Coordinator::Write::Events::ReleaseSetMemberAddedV1)
          prepared = payload!(source, Coordinator::Write::Events::ReleaseSetPreparedV2)
          prepared_event = event_for_payload(source, prepared)
          @completion_builder.release_set_prepare(
            **args,
            change_set_id: created.change_set_id,
            ordered_members: members.map do |member|
              Coordinator::Write::ReleaseSets::MemberSummaryV2.new(
                position: member.member_position,
                repository_id: member.repository_id,
                candidate_id: member.candidate_id
              )
            end,
            release_digest: prepared_event.metadata.fetch("release_digest"),
            prepared_event:
          )
        when "release_repository_integration_record"
          integration = payload!(source, Coordinator::Write::Events::RepositoryIntegrationRecordedV2)
          integration_event = event_for_payload(source, integration)
          @completion_builder.release_repository_integration_record(
            **args,
            integration:,
            integration_digest: integration_event.metadata.fetch("integration_digest"),
            integration_event:
          )
        when "release_verification_record"
          verification = payload!(source, Coordinator::Write::Events::ReleaseSetVerificationRecordedV2)
          verification_event = event_for_payload(source, verification)
          @completion_builder.release_verification_record(
            **args,
            verification:,
            integration_events: payloads(source).grep(Coordinator::Write::Events::ReleaseSetIntegrationLinkedV1).map(&:integration_event),
            verification_digest: verification_event.metadata.fetch("verification_digest"),
            verification_event:
          )
        when "release_activation_record"
          activation = payload!(source, Coordinator::Write::Events::ReleaseSetActivatedV2)
          activation_event = event_for_payload(source, activation)
          @completion_builder.release_activation_record(
            **args,
            activation:,
            activation_digest: activation_event.metadata.fetch("activation_digest"),
            activation_event:
          )
        when "release_compensation_complete"
          outcome = payload!(source, Coordinator::Write::Events::ReleaseSetOutcomeRecordedV1)
          completion_event = event_for_payload(
            source,
            payload!(source, Coordinator::Write::Events::ReleaseSetCompletedV2)
          )
          preparation = @release_set_preparation_loader.call(outcome.release_set_id)
          @completion_builder.release_compensation_complete(
            **args,
            change_set_id: preparation.change_set_id,
            outcome: outcome.outcome,
            source_event: source.command.compensation_request_event,
            completion_digest: event_for_payload(source, outcome).metadata.fetch("completion_digest"),
            completion_event:
          )
        when "skill_publish" then skill_publication(source, args:)
        when "development_artifact_capture" then development_artifact_capture(source, args:)
        when "development_artifact_update" then development_artifact_update(source)
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
        activation = payload!(source, Coordinator::Write::Events::DecisionActivatedV2)
        recorded = payload!(source, Coordinator::Write::Events::DecisionRecordedV2)
        definition = Coordinator::Write::Decisions::DecisionDefinitionV1.new(
          document: recorded.definition,
          digest: Coordinator::Write::CanonicalJson.new.sha256(recorded.definition.to_h)
        )
        opened = payload(source, Coordinator::Write::Events::DecisionSlotOpenedV2)
        slot = if opened
                 generated = Coordinator::Write::Decisions::DecisionSlotBuilder.new.call(definition)
                 Coordinator::Write::Decisions::DecisionSlotV1.new(
                   slot_id: opened.slot_id,
                   document: opened.slot,
                   compound_marker: generated.compound_marker
                 )
               end
        @completion_builder.decision_activate(
          **args,
          activation:,
          definition_digest: definition.digest,
          slot:,
          partitions: activation_partition_receipts(source, definition)
        )
      end

      def write_set_expansion(source, args:)
        command = source.command
        memberships = @event_store.read(
          @stream_factory.work_intention_set(command.lease_set_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ "WorkIntentionAddedToSet" ],
            maximum_count: Coordinator::Shared::Types::WRITE_SET_RESOURCE_MAXIMUM_COUNT,
            direction: :asc
          )
        ).map { load_payload(_1) }
        declarations = memberships.map do |membership|
          event = @event_store.read_grouped(
            @stream_factory.resource_work_intention(membership.intention_id),
            Coordinator::Write::EventQueries::WORK_INTENTION_STATE
          )
          declared = event.find { _1.type == "ResourceWorkIntentionDeclared" }
          latest = event.find { _1.type == "ResourceWorkIntentionRenewed" } || declared
          [ load_payload(declared), load_payload(latest) ]
        end
        emitted_declarations = payloads(source).grep(
          Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1
        )
        added_resources = emitted_declarations.map { lease_reference_for(_1) }
        expiration = declarations.map { |declared, latest| latest.expires_at || declared.expires_at }.min
        expansion = Coordinator::Write::WorkIntentionSetExpansionReceiptV1.new(
          lease_set_id: command.lease_set_id,
          repository_id: command.repository_id,
          policy_version: Coordinator::Write::WorkIntentionPolicyV1::VERSION,
          expanded_at: source.persisted_events.first&.created_at&.utc&.iso8601(6) || source.completed_at,
          expires_at: expiration,
          added_resources:,
          resource_count: memberships.length
        )
        @completion_builder.write_set_expand(**args, expansion:)
      end

      def write_set_reservation(source, args:)
        created = payload!(source, Coordinator::Write::Events::WorkIntentionSetCreatedV1)
        evidence = work_intention_set_evidence(source, created.set_id)
        reservation = Coordinator::Write::WorkIntentionSetReceiptV1.new(
          lease_set_id: evidence.set_id,
          repository_id: evidence.repository_id,
          policy_version: Coordinator::Write::WorkIntentionPolicyV1::VERSION,
          reserved_at: evidence.created_at,
          expires_at: evidence.current_expires_at,
          resources: evidence.resources
        )
        @completion_builder.write_set_reserve(**args, reservation:)
      end

      def work_intention_set_renewal(source, args:)
        evidence = work_intention_set_evidence(source, source.command.lease_set_id)
        renewal = Coordinator::Write::WorkIntentionSetRenewalReceiptV1.new(
          lease_set_id: evidence.set_id,
          repository_id: evidence.repository_id,
          policy_version: Coordinator::Write::WorkIntentionPolicyV1::VERSION,
          resources: evidence.resources,
          resource_count: evidence.resources.length,
          renewed_at: source.completed_at,
          previous_expires_at: evidence.before_command_expires_at || evidence.current_expires_at,
          expires_at: evidence.current_expires_at
        )
        @completion_builder.lease_renew(**args, renewal:)
      end

      def work_intention_set_release(source, args:)
        evidence = work_intention_set_evidence(source, source.command.lease_set_id)
        release = Coordinator::Write::WorkIntentionSetWithdrawalReceiptV1.new(
          lease_set_id: evidence.set_id,
          repository_id: evidence.repository_id,
          policy_version: Coordinator::Write::WorkIntentionPolicyV1::VERSION,
          resources: evidence.resources,
          resource_count: evidence.resources.length,
          previous_expires_at: evidence.current_expires_at,
          released_at: source.completed_at
        )
        @completion_builder.lease_release(**args, release:)
      end

      def work_intention_set_evidence(source, set_id)
        @work_intention_set_evidence_loader.call(
          set_id,
          excluding_event_ids: source.persisted_events.map(&:id)
        )
      end

      def lease_reference_for(declaration)
        registration = load_payload(resource_registration(declaration.resource_id))
        Coordinator::Write::LeaseReferenceV2.new(
          lease_id: declaration.intention_id,
          resource_id: declaration.resource_id,
          resource_kind: registration.kind,
          resource_path: registration.normalized_path,
          base_blob_oid: declaration.base_blob_oid,
          fencing_token: declaration.fencing_token
        )
      end

      def activation_partition_receipts(source, definition)
        partitions = Coordinator::Write::Decisions::DecisionPartitionBuilder.new.call(definition)
          .to_h { [ _1.partition_id, _1 ] }
        payloads(source).filter_map.with_index do |candidate, index|
          next unless candidate.is_a?(Coordinator::Write::Events::DecisionAddedToPartitionV1)

          Coordinator::Write::Decisions::DecisionPartitionReceiptV1.new(
            partition: partitions.fetch(candidate.partition_id),
            partition_revision: source.persisted_events.fetch(index).stream_revision
          )
        end
      end

      def decision_correction(source, args:)
        correction = payload!(source, Coordinator::Write::Events::DecisionDefinitionCorrectedV2)
        correction_event = event_for_payload(source, correction)
        previous_document = previous_decision_definition(
          correction.decision_id,
          before_revision: correction_event.stream_revision
        )
        current = decision_definition(previous_document)
        candidate = decision_definition(correction.definition)
        slot = correction_slot(source, candidate)
        @completion_builder.decision_correct(
          **args,
          correction:,
          previous_definition_digest: current.digest,
          definition_digest: candidate.digest,
          slot:,
          correction_event: event_reference(correction_event),
          partitions: correction_partition_receipts(source, current, candidate)
        )
      end

      def previous_decision_definition(decision_id, before_revision:)
        events = @event_store.read(
          @stream_factory.decision(decision_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ "DecisionRecorded", "DecisionDefinitionCorrected" ],
            maximum_count: 33,
            direction: :asc
          )
        )
        event = events.select { _1.stream_revision < before_revision }.last
        raise InvalidProjectionSource, "decision_correct is missing previous Decision definition" unless event

        load_payload(event).definition
      end

      def decision_definition(document)
        Coordinator::Write::Decisions::DecisionDefinitionV1.new(
          document:,
          digest: Coordinator::Write::CanonicalJson.new.sha256(document.to_h)
        )
      end

      def correction_slot(source, definition)
        change = payloads(source).grep(Coordinator::Write::Events::DecisionSlotHeadChangedV2)
          .reverse
          .find { _1.head&.decision_id == source.command.decision_id }
        return unless change

        generated = Coordinator::Write::Decisions::DecisionSlotBuilder.new.call(definition)
        Coordinator::Write::Decisions::DecisionSlotV1.new(
          slot_id: change.slot_id,
          document: generated.document,
          compound_marker: generated.compound_marker
        )
      end

      def correction_partition_receipts(source, current, candidate)
        partitions = (
          Coordinator::Write::Decisions::DecisionPartitionBuilder.new.call(current) +
          Coordinator::Write::Decisions::DecisionPartitionBuilder.new.call(candidate)
        ).to_h { [ _1.partition_id, _1 ] }
        payloads(source).filter_map.with_index do |payload, index|
          next unless payload.is_a?(Coordinator::Write::Events::DecisionAddedToPartitionV1) ||
                      payload.is_a?(Coordinator::Write::Events::DecisionRemovedFromPartitionV1)

          Coordinator::Write::Decisions::DecisionPartitionReceiptV1.new(
            partition: partitions.fetch(payload.partition_id),
            partition_revision: source.persisted_events.fetch(index).stream_revision
          )
        end
      end

      def skill_publication(source, args:)
        publication_event = event_for_any_payload(
          source,
          Coordinator::Write::Events::SkillRevisionPublishedV3,
          Coordinator::Write::Events::SkillRevisionPublishedV2
        ) || load_first_event(
          @stream_factory.skill(source.command.skill_id),
          Coordinator::Write::EventQueries::SKILL_LATEST_REVISION
        )
        publication = load_payload(publication_event)
        revision = publication.revision
        outcome = source.persisted_events.any? { _1.type == "SkillRevisionPublished" } ? "published" : "existing"
        @completion_builder.skill_publish(
          **args,
          revision:,
          outcome:,
          publication_event:
        )
      end

      def development_artifact_capture(source, args:)
        command = source.command
        created_event = event_for_any_payload(
          source,
          Coordinator::Write::Events::DevelopmentArtifactCreatedV1
        )
        recorded_event = event_for_any_payload(
          source,
          Coordinator::Write::Events::DevelopmentArtifactObservationRecordedV1
        )
        legacy_observed_event = event_for_any_payload(
          source,
          Coordinator::Write::Events::DevelopmentArtifactObservedV1
        )
        capture_event = event_for_any_payload(
          source,
          Coordinator::Write::Events::DevelopmentArtifactCapturedV2
        )
        if created_event || recorded_event || source.persisted_events.empty?
          artifact = command.artifact
          observed = command.observation
          outcome = if created_event
                      "captured"
                    elsif recorded_event
                      "observed"
                    else
                      "existing"
                    end
          recorded_at = event_timestamp(recorded_event || created_event) || source.completed_at
        else
          observation = payload(source, Coordinator::Write::Events::DevelopmentArtifactObservedV1) ||
                        load_observation(command.observation.observation_id).observation
          capture = payload(source, Coordinator::Write::Events::DevelopmentArtifactCapturedV2) || load_first(
            @stream_factory.development_artifact(observation.observation.artifact_id),
            Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_CAPTURE
          )
          artifact = capture.artifact
          observed = observation.observation
          outcome = legacy_observed_event ? "observed" : "existing"
          recorded_at = event_timestamp(legacy_observed_event || capture_event) || source.completed_at
        end
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
            recorded_at:
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
        command = source.command
        history = load_observation_payloads(command.observation_id)
        granular = history.any? do |event|
          event.is_a?(Coordinator::Write::Events::DevelopmentArtifactObservationRecordedV1) ||
            event.is_a?(Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1) ||
            event.is_a?(Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectionRecordedV1)
        end
        correction = payload(source, Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectedV1)
        correction_record = payload(
          source,
          Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectionRecordedV1
        )
        outcome = correction || correction_record ? "corrected" : "existing"
        state = granular ? nil : ArtifactObservationState.reduce(history)
        artifact_id = correction&.artifact_id || correction_record&.artifact_id ||
          (granular ? observation_artifact_id(history) : state.observation.observation.artifact_id)
        title = correction&.title || command.title || state&.title
        kind = correction&.kind || command.kind || state&.kind
        labels = correction&.labels || command.labels || state&.labels
        revision = correction&.classification_revision || correction_record&.classification_revision ||
          (granular ? granular_classification_revision(history) : state.classification_revision)
        corrected_event = event_for_any_payload(
          source,
          Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectedV1,
          Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectionRecordedV1
        )
        raise InvalidProjectionSource, "Classification source has no Artifact identity" unless artifact_id
        raise InvalidProjectionSource, "Classification source has incomplete values" unless title && kind && labels
        completion(
          source,
          summary: outcome == "corrected" ?
            "Development Artifact observation classification corrected." :
            "Development Artifact observation classification is already current.",
          data: Coordinator::Write::CommandReceiptData::DevelopmentArtifactClassification.new(
            artifact_id:,
            observation_id: command.observation_id,
            classification_revision: revision,
            title:,
            kind:,
            labels:,
            outcome:,
            corrected_at: corrected_event&.created_at&.utc&.iso8601(6) || source.completed_at
          ),
          next_actions: [
            Coordinator::Write::NextAction.new(
              tool: "development_artifact_get",
              arguments: Coordinator::Write::NextAction::DevelopmentArtifactArguments.new(
                artifact_id:,
                observation_id: command.observation_id
              )
            )
          ]
        )
      end

      def development_artifact_update(source)
        command = source.command
        property_event_types = %w[
          DevelopmentArtifactScopeChanged
          DevelopmentArtifactTitleChanged
          DevelopmentArtifactKindChanged
          DevelopmentArtifactLabelAdded
          DevelopmentArtifactLabelRemoved
          DevelopmentArtifactSourceChanged
          DevelopmentArtifactContentChanged
        ]
        unless source.persisted_events.all? { |event| property_event_types.include?(event.type) }
          raise InvalidProjectionSource, "Development Artifact update contains unsupported source evidence"
        end
        source.persisted_events.each_with_index do |event, index|
          payload = source.payloads.fetch(index)
          unless event.stream.stream_id == command.artifact_id &&
                 payload.respond_to?(:artifact_id) && payload.artifact_id == command.artifact_id
            raise InvalidProjectionSource, "Development Artifact update source does not match its command"
          end
        end
        property_events = source.persisted_events
        changed_properties = property_events.filter_map do |event|
          {
            "DevelopmentArtifactScopeChanged" => "scope",
            "DevelopmentArtifactTitleChanged" => "title",
            "DevelopmentArtifactKindChanged" => "kind",
            "DevelopmentArtifactLabelAdded" => "labels",
            "DevelopmentArtifactLabelRemoved" => "labels",
            "DevelopmentArtifactSourceChanged" => "source",
            "DevelopmentArtifactContentChanged" => "content"
          }[event.type]
        end.uniq
        outcome = changed_properties.empty? ? "existing" : "updated"
        latest_event = property_events.last
        completion(
          source,
          summary: outcome == "updated" ?
            "Development Artifact properties updated as granular facts." :
            "Development Artifact already has the requested properties.",
          data: Coordinator::Write::CommandReceiptData::DevelopmentArtifactUpdate.new(
            artifact_id: command.artifact_id,
            resulting_stream_revision: latest_event&.stream_revision || command.expected_revision,
            changed_properties:,
            outcome:,
            updated_at: latest_event&.created_at&.utc&.iso8601(6) || source.completed_at
          ),
          next_actions: [
            Coordinator::Write::NextAction.new(
              tool: "development_artifact_get",
              arguments: Coordinator::Write::NextAction::DevelopmentArtifactArguments.new(
                artifact_id: command.artifact_id
              )
            )
          ]
        )
      end

      def development_artifact_relation(source, args:)
        command = source.command
        declaration_event = event_for_any_payload(
          source,
          Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV1,
          Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV2
        ) || load_artifact_relation_event(command)
        declaration = load_payload(declaration_event)
        artifact_relation = relation_from_declaration(declaration)
        supersession = payload(source, Coordinator::Write::Events::DevelopmentArtifactRelationSupersededV1) ||
                       payload(source, Coordinator::Write::Events::DevelopmentArtifactRelationSupersededV2)
        supersession_event = event_for_any_payload(
          source,
          Coordinator::Write::Events::DevelopmentArtifactRelationSupersededV1,
          Coordinator::Write::Events::DevelopmentArtifactRelationSupersededV2
        )
        outcome = if supersession
                    "superseded"
                  elsif source.persisted_events.empty?
                    "existing"
                  else
                    "declared"
                  end
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
            superseded_relation_id: superseded_relation_id(supersession),
            outcome:,
            declared_at: declaration_event.created_at.utc.iso8601(6),
            superseded_at: supersession_event&.created_at&.utc&.iso8601(6)
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

      def relation_from_declaration(declaration)
        return declaration.artifact_relation if declaration.is_a?(
          Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV1
        )

        Coordinator::Write::DevelopmentArtifacts::RelationV1.new(
          relation_id: declaration.relation_id,
          source_artifact_id: declaration.source_artifact_id,
          relation: declaration.relation,
          target: Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
            kind: declaration.target_kind,
            id: declaration.target_id,
            status: declaration.target_kind == "external" ? "unverified" : "verified",
            name: nil,
            scope: nil
          ),
          attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(
            path: declaration.path,
            fragment: declaration.fragment,
            normalized_locator: declaration.normalized_locator
          )
        )
      end

      def superseded_relation_id(supersession)
        return unless supersession

        supersession.respond_to?(:superseded_relation_id) ?
          supersession.superseded_relation_id : supersession.relation_id
      end

      def repository_registration(source)
        registration_event = event_for_any_payload(
          source,
          Coordinator::Write::Events::RepositoryRegisteredV2,
          Coordinator::Write::Events::RepositoryRegisteredV1
        )
        registration_event ||= load_repository_registration_event(source.command)
        registration = @repository_registration_loader.call(registration_event.stream.stream_id)
        raise InvalidProjectionSource, "Canonical Repository registration is incomplete" unless registration
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
            registered_at: registration_event.created_at.utc.iso8601(6)
          )
        )
      end

      def resource_resolution(source)
        command = source.command
        registration_event = event_for_any_payload(
          source,
          Coordinator::Write::Events::ResourceIdentityV2::Registered,
          Coordinator::Write::Events::ResourceIdentityV1::Registered
        )
        binding_event = event_for_any_payload(
          source,
          Coordinator::Write::Events::ResourceIdentityV2::Bound,
          Coordinator::Write::Events::ResourceIdentityV1::Bound
        )
        outcome = if registration_event
                    "registered"
                  elsif binding_event
                    "reactivated"
                  else
                    "existing"
                  end
        binding_event ||= current_resource_binding(command.identity.current_path_marker)
        binding = load_payload(binding_event)
        registration_event ||= resource_registration(binding.resource_id)
        registration = load_payload(registration_event)
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
            registered_at: registration_event.created_at.utc.iso8601(6),
            bound_at: binding_event.created_at.utc.iso8601(6)
          )
        )
      end

      def resource_removal(source)
        command = source.command
        registration_event = resource_registration(command.resource_id)
        registration = load_payload(registration_event)
        unbinding_event = event_for_any_payload(
          source,
          Coordinator::Write::Events::ResourceIdentityV2::Unbound,
          Coordinator::Write::Events::ResourceIdentityV1::Unbound
        )
        outcome = unbinding_event ? "removed" : "already_inactive"
        completion(
          source,
          summary: unbinding_event ? "Resource binding removed." : "Resource binding was already inactive.",
          data: Coordinator::Write::CommandReceiptData::ResourceRemoval.new(
            resource_id: registration.resource_id,
            repository_id: registration.repository_id,
            kind: registration.kind,
            normalized_path: registration.normalized_path,
            outcome:,
            reason: command.reason,
            unbound_at: unbinding_event&.created_at&.utc&.iso8601(6) || source.completed_at
          )
        )
      end

      def abandonment_completion(source)
        abandonment = payload!(source, Coordinator::Write::Events::AttemptAbandonedV3)
        payload!(source, Coordinator::Write::Events::WorkItemRequeuedV2)
        withdrawn_count = payloads(source).count do |payload|
          payload.is_a?(Coordinator::Write::Events::ResourceWorkIntentionWithdrawnV1)
        end
        member_count = @work_intention_set_evidence_loader.member_count_for_attempt(abandonment.attempt_id)
        untouched_count = member_count - withdrawn_count
        if untouched_count.negative?
          raise InvalidProjectionSource, "Attempt abandonment withdrew more intentions than its set contains"
        end
        warnings = [ "Reacquire the WorkItem with a fresh Attempt ID and base snapshot before resuming." ]
        if untouched_count.positive?
          warnings << "#{untouched_count} work intention(s) were already inactive and were left unchanged."
        end
        completion(
          source,
          summary: "Attempt abandoned; WorkItem requeued; #{withdrawn_count} active work intention(s) withdrawn.",
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

      def event_for_any_payload(source, *payload_classes)
        payload = source.payloads.find { |candidate| payload_classes.any? { candidate.is_a?(_1) } }
        payload && event_for_payload(source, payload)
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

      def event_timestamp(event)
        event&.created_at&.utc&.iso8601(6)
      end

      def load_first(stream, criteria)
        load_payload(load_first_event(stream, criteria))
      end

      def load_first_event(stream, criteria)
        event = @event_store.read(stream, criteria).first
        raise InvalidProjectionSource, "Required command-result source event does not exist" unless event

        event
      end

      def load_observation(observation_id)
        ArtifactObservationState.reduce(load_observation_payloads(observation_id))
      end

      def load_observation_payloads(observation_id)
        @event_store.read(
          @stream_factory.development_artifact_observation(observation_id),
          Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_OBSERVATION_HISTORY
        ).map { load_payload(_1) }
      end

      def observation_artifact_id(history)
        history.filter_map do |event|
          case event
          when Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1
            event.artifact_id
          when Coordinator::Write::Events::DevelopmentArtifactObservedV1
            event.observation.artifact_id
          end
        end.first
      end

      def granular_classification_revision(history)
        1 + history.count do |event|
          event.is_a?(Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectionRecordedV1)
        end
      end

      def load_artifact_relation_event(command)
        marker = @development_artifact_marker_builder.relation_natural_key(command.artifact_relation)
        event = %w[DevelopmentArtifact DevelopmentArtifactRelation].lazy.map do |stream_name|
          @event_store.read_global_marked(
            Coordinator::Write::GlobalMarkedEventReadCriteria.new(
              stream_context: "DevelopmentMemory",
              stream_name:,
              event_types: [ "DevelopmentArtifactRelationDeclared" ],
              markers: [ marker ],
              maximum_count: 1,
              direction: :asc
            )
          ).first
        end.find(&:itself)
        raise InvalidProjectionSource, "Development Artifact relation source does not exist" unless event

        event
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

        event
      end

      def resource_registration(resource_id)
        load_first_event(
          @stream_factory.resource(resource_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: [ "ResourceRegistered" ],
            maximum_count: 1,
            direction: :asc
          )
        )
      end

      def load_repository_registration_event(command)
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

        event
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
