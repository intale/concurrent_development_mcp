# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class WorkItemV1Transformer
      include Dry::Monads[:result]

      def initialize(
        stream_identity_allocator:,
        entity_reference_resolver:,
        marked_event_locator:,
        target_event_reference_resolver:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @marked_event_locator = marked_event_locator
        @target_event_reference_resolver = target_event_reference_resolver
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        work_item = resolve_work_item(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_payload
        )
        return work_item if work_item.failure?

        transform(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_payload,
          target_stream: work_item.value!.target_stream
        )
      end

      private

      def transform(migration_id:, source_config_name:, source_upper_position:, source_event:, source:, target_stream:)
        case source
        when Events::WorkItemCreatedV1
          created_facts(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::WorkItemAddedToChangeSetV1
          membership_fact(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::WorkItemDependencyDeclaredV1
          dependency_declared_fact(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::WorkItemDependencySatisfiedV1
          dependency_satisfied_fact(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::WorkItemMadeReadyV1
          made_ready_fact(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::WorkItemAcquiredV1
          acquired_fact(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::WorkItemRequeuedV1
          requeued_fact(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::WorkItemCandidateSelectedV1
          candidate_selected_fact(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::WorkItemCompletedV1
          Success(completed_facts(source, target_stream:))
        end
      end

      def created_facts(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        change_set = resolve_change_set(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_id: source.change_set_id
        )
        return change_set if change_set.failure?

        repository = resolve_repository(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_id: source.repository_id
        )
        return repository if repository.failure?

        work_item_id = target_stream.stream_id
        change_set_id = change_set.value!.target_stream.stream_id
        repository_id = repository.value!.target_stream.stream_id
        common = markers(work_item_id:, change_set_id:, repository_id:)
        Success([
          fact(
            target_stream:,
            event: Events::WorkItemCreatedV2.new(work_item_id:),
            markers: common,
            step_name: "create-work-item"
          ),
          fact(
            target_stream:,
            event: Events::WorkItemAssignedToRepositoryV1.new(work_item_id:, repository_id:),
            markers: common,
            step_name: "assign-work-item-to-repository"
          ),
          fact(
            target_stream:,
            event: Events::WorkItemGoalDefinedV1.new(work_item_id:, goal: source.goal),
            markers: common,
            step_name: "define-work-item-goal"
          ),
          fact(
            target_stream:,
            event: Events::WorkItemAcceptanceCriteriaDefinedV1.new(
              work_item_id:,
              acceptance_criteria: source.acceptance_criteria
            ),
            markers: common,
            step_name: "define-work-item-acceptance-criteria"
          ),
          fact(
            target_stream:,
            event: Events::WorkItemCompetitiveModeSelectedV1.new(
              work_item_id:,
              competitive_mode: source.competitive_mode
            ),
            markers: common,
            step_name: "select-work-item-competitive-mode"
          )
        ])
      end

      def membership_fact(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        change_set = resolve_change_set(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_id: source.change_set_id
        )
        return change_set if change_set.failure?

        work_item_id = target_stream.stream_id
        change_set_id = change_set.value!.target_stream.stream_id
        Success([
          fact(
            target_stream:,
            event: Events::WorkItemAddedToChangeSetV2.new(work_item_id:, change_set_id:),
            markers: markers(work_item_id:, change_set_id:),
            step_name: "add-work-item-to-change-set"
          )
        ])
      end

      def dependency_declared_fact(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        relationships = resolve_dependency_relationships(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source:
        )
        return relationships if relationships.failure?

        change_set_id, producer_work_item_id = relationships.value!
        consumer_work_item_id = target_stream.stream_id
        dependency_id = source_event.id
        Success([
          fact(
            target_stream:,
            event: Events::WorkItemDependencyDeclaredV2.new(
              dependency_id:,
              change_set_id:,
              producer_work_item_id:,
              consumer_work_item_id:,
              dependency_kind: source.dependency_kind,
              required_output: source.required_output
            ),
            markers: dependency_markers(
              dependency_id:,
              change_set_id:,
              producer_work_item_id:,
              consumer_work_item_id:
            ),
            step_name: "declare-work-item-dependency"
          )
        ])
      end

      def dependency_satisfied_fact(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        declaration = @marked_event_locator.call(
          source_event:,
          source_upper_position:,
          stream_context: "DevelopmentPlanning",
          stream_name: "ChangeSet",
          event_type: "WorkItemDependencyDeclared",
          marker: "dependency:#{source.dependency_id}"
        )
        return declaration if declaration.failure?
        return Failure(invalid_dependency_reference(source_event, source:)) unless matching_declaration?(declaration.value!, source)

        relationships = resolve_dependency_relationships(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source:
        )
        return relationships if relationships.failure?

        target_source = @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.source_event,
          target_stream_context: "DevelopmentExecution",
          target_stream_name: "WorkItem",
          identity_role: "work-item",
          target_event_type: "WorkItemCompleted",
          target_step_name: "complete-work-item"
        )
        return target_source if target_source.failure?

        change_set_id, producer_work_item_id = relationships.value!
        consumer_work_item_id = target_stream.stream_id
        dependency_id = declaration.value!.id
        Success([
          fact(
            target_stream:,
            event: Events::WorkItemDependencySatisfiedV2.new(
              dependency_id:,
              change_set_id:,
              producer_work_item_id:,
              consumer_work_item_id:,
              dependency_kind: source.dependency_kind,
              required_output: source.required_output,
              source: target_source.value!
            ),
            markers: dependency_markers(
              dependency_id:,
              change_set_id:,
              producer_work_item_id:,
              consumer_work_item_id:
            ),
            step_name: "satisfy-work-item-dependency",
            policy_version: source.rule_version
          )
        ])
      end

      def made_ready_fact(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        change_set = resolve_change_set(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_id: source.change_set_id
        )
        return change_set if change_set.failure?

        work_item_id = target_stream.stream_id
        change_set_id = change_set.value!.target_stream.stream_id
        readiness_decision_id = source_event.id
        Success([
          fact(
            target_stream:,
            event: Events::WorkItemMadeReadyV2.new(
              work_item_id:,
              change_set_id:,
              readiness_decision_id:,
              reason: source.reason
            ),
            markers: markers(work_item_id:, change_set_id:) +
              [ "readiness-decision:#{readiness_decision_id}" ],
            step_name: "make-work-item-ready"
          )
        ])
      end

      def acquired_fact(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        linked = resolve_attempt_relationships(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source:
        )
        return linked if linked.failure?

        change_set_id, attempt_id = linked.value!
        work_item_id = target_stream.stream_id
        Success([
          fact(
            target_stream:,
            event: Events::WorkItemAcquiredV2.new(
              work_item_id:,
              change_set_id:,
              attempt_id:,
              agent_id: source.agent_id
            ),
            markers: markers(work_item_id:, change_set_id:, attempt_id:),
            step_name: "acquire-work-item"
          )
        ])
      end

      def requeued_fact(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        linked = resolve_attempt_relationships(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source:
        )
        return linked if linked.failure?

        change_set_id, attempt_id = linked.value!
        work_item_id = target_stream.stream_id
        Success([
          fact(
            target_stream:,
            event: Events::WorkItemRequeuedV2.new(
              work_item_id:,
              change_set_id:,
              attempt_id:,
              agent_id: source.agent_id,
              reason: source.reason
            ),
            markers: markers(work_item_id:, change_set_id:, attempt_id:),
            step_name: "requeue-work-item"
          )
        ])
      end

      def completed_facts(source, target_stream:)
        work_item_id = target_stream.stream_id
        extension = MigrationMetadataExtensionV1.new(policy_version: source.rule_version)
        output_facts = source.produced_outputs.each_with_index.map do |output, index|
          TransformedFactV1.new(
            target_stream:,
            event: Events::WorkItemOutputRecordedV1.new(
              work_item_id:,
              output_kind: output.kind,
              output_key: output.key
            ),
            markers: markers(work_item_id:),
            step_name: format("record-work-item-output-%02d", index + 1),
            metadata_extension: extension
          )
        end
        output_facts << fact(
          target_stream:,
          event: Events::WorkItemCompletedV2.new(work_item_id:),
          markers: markers(work_item_id:),
          step_name: "complete-work-item",
          policy_version: source.rule_version
        )
      end

      def candidate_selected_fact(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        relationships = resolve_attempt_relationships(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source:
        )
        return relationships if relationships.failure?

        candidate = @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.candidate_event,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "Candidate",
          identity_role: "candidate",
          target_event_type: "CandidateSubmitted",
          target_step_name: "submit-candidate"
        )
        return candidate if candidate.failure?

        change_set_id, attempt_id = relationships.value!
        work_item_id = target_stream.stream_id
        target_candidate = candidate.value!
        Success([
          fact(
            target_stream:,
            event: Events::WorkItemCandidateSelectedV2.new(
              work_item_id:,
              change_set_id:,
              attempt_id:,
              candidate_id: target_candidate.stream_id,
              candidate_event: target_candidate
            ),
            markers: markers(
              work_item_id:,
              change_set_id:,
              attempt_id:
            ) + [ "candidate:#{target_candidate.stream_id}" ],
            step_name: "select-work-item-candidate"
          )
        ])
      end

      def resolve_work_item(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        if source_event.stream.context == "DevelopmentExecution" &&
            source_event.stream.stream_name == "WorkItem"
          return @stream_identity_allocator.call(
            migration_id:,
            source_config_name:,
            source_event:,
            target_stream_context: "DevelopmentExecution",
            target_stream_name: "WorkItem",
            identity_role: "work-item"
          )
        end

        resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentExecution",
          source_name: "WorkItem",
          source_id: work_item_source_id(source),
          target_context: "DevelopmentExecution",
          target_name: "WorkItem",
          identity_role: "work-item"
        )
      end

      def resolve_dependency_relationships(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        change_set = resolve_change_set(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_id: source.change_set_id
        )
        return change_set if change_set.failure?

        producer = resolve_work_item_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_id: source.producer_work_item_id
        )
        return producer if producer.failure?

        Success([
          change_set.value!.target_stream.stream_id,
          producer.value!.target_stream.stream_id
        ])
      end

      def resolve_attempt_relationships(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        change_set = resolve_change_set(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_id: source.change_set_id
        )
        return change_set if change_set.failure?

        attempt = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentExecution",
          source_name: "Attempt",
          source_id: source.attempt_id,
          target_context: "DevelopmentExecution",
          target_name: "Attempt",
          identity_role: "attempt"
        )
        return attempt if attempt.failure?

        Success([
          change_set.value!.target_stream.stream_id,
          attempt.value!.target_stream.stream_id
        ])
      end

      def resolve_change_set(**arguments)
        resolve_entity(
          **arguments,
          source_context: "DevelopmentPlanning",
          source_name: "ChangeSet",
          target_context: "DevelopmentPlanning",
          target_name: "ChangeSet",
          identity_role: "change-set"
        )
      end

      def resolve_repository(**arguments)
        resolve_entity(
          **arguments,
          source_context: "DevelopmentPlanning",
          source_name: "Repository",
          target_context: "DevelopmentPlanning",
          target_name: "Repository",
          identity_role: "repository"
        )
      end

      def resolve_work_item_reference(**arguments)
        resolve_entity(
          **arguments,
          source_context: "DevelopmentExecution",
          source_name: "WorkItem",
          target_context: "DevelopmentExecution",
          target_name: "WorkItem",
          identity_role: "work-item"
        )
      end

      def resolve_entity(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_context:,
        source_name:,
        source_id:,
        target_context:,
        target_name:,
        identity_role:
      )
        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: source_context,
            stream_name: source_name,
            stream_id: source_id
          ),
          target_stream_context: target_context,
          target_stream_name: target_name,
          identity_role:
        )
      end

      def matching_declaration?(event, source)
        declaration = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        declaration.is_a?(Events::WorkItemDependencyDeclaredV1) &&
          declaration.dependency_id == source.dependency_id &&
          declaration.change_set_id == source.change_set_id &&
          declaration.producer_work_item_id == source.producer_work_item_id &&
          declaration.consumer_work_item_id == source.consumer_work_item_id
      rescue KeyError, ArgumentError, Dry::Struct::Error
        false
      end

      def work_item_source_id(source)
        case source
        when Events::WorkItemDependencyDeclaredV1, Events::WorkItemDependencySatisfiedV1
          source.consumer_work_item_id
        else
          source.work_item_id
        end
      end

      def invalid_dependency_reference(source_event, source:)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Historical dependency declaration does not match #{source.dependency_id}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end

      def fact(target_stream:, event:, markers:, step_name:, policy_version: nil)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension: policy_version && MigrationMetadataExtensionV1.new(policy_version:)
        )
      end

      def markers(work_item_id:, change_set_id: nil, repository_id: nil, attempt_id: nil)
        [
          "work-item:#{work_item_id}",
          ("change-set:#{change_set_id}" if change_set_id),
          ("repository:#{repository_id}" if repository_id),
          ("attempt:#{attempt_id}" if attempt_id)
        ].compact
      end

      def dependency_markers(dependency_id:, change_set_id:, producer_work_item_id:, consumer_work_item_id:)
        [
          "change-set:#{change_set_id}",
          "dependency:#{dependency_id}",
          "work-item:#{producer_work_item_id}",
          "work-item:#{consumer_work_item_id}"
        ]
      end
    end
  end
end
