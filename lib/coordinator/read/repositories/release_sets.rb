# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class ReleaseSets
      def fetch(release_set_id)
        record = Coordinator::Read::ReleaseSet.find_by(release_set_id:)
        record && build_view(record)
      end

      private

      def build_view(record)
        ReleaseSetViewV1.new(
          release_set_id: record.release_set_id,
          change_set_id: record.change_set_id,
          ordered_members: record.ordered_members.map { ReleaseSetMemberViewV1.new(symbolize(_1)) },
          release_digest: record.release_digest,
          status: record.status,
          verification_status: record.verification_status,
          integrations: record.integrations.map { build_integration(_1) },
          verifications: record.verifications.map { build_verification(_1) },
          activation: record.activation && build_activation(record.activation),
          compensation_request: record.compensation_request && build_compensation_request(record.compensation_request),
          completion: record.completion&.key?("outcome") && build_completion(record.completion),
          preparation_policy_version: record.preparation_policy_version,
          prepared_at: record.prepared_at_domain.utc.iso8601(6),
          prepared: source_evidence(record)
        )
      end

      def build_integration(attributes)
        values = symbolize(attributes)
        ReleaseSetIntegrationViewV1.new(
          **values,
          merge_observation_event: event_reference_value(values[:merge_observation_event]),
          failure: integration_failure_value(values[:failure]),
          source: source_evidence_value(values.fetch(:source))
        )
      end

      def build_verification(attributes)
        values = symbolize(attributes)
        ReleaseSetVerificationViewV1.new(
          **values.except(:integration_link_events),
          integration_events: values.fetch(:integration_events).map { Coordinator::Write::EventReference.new(_1) },
          evidence: verification_evidence_value(values.fetch(:evidence)),
          source: source_evidence_value(values.fetch(:source))
        )
      end

      def build_activation(attributes)
        values = symbolize(attributes)
        point = values.fetch(:activation_point)
        ReleaseSetActivationViewV1.new(
          **values,
          verification_event: event_reference_value(values[:verification_event]),
          activation_point: Coordinator::Write::ReleaseSets::ActivationPointV2.new(
            **point,
            producer: Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(point.fetch(:producer))
          ),
          source: source_evidence_value(values.fetch(:source))
        )
      end

      def build_compensation_request(attributes)
        values = symbolize(attributes)
        ReleaseSetCompensationRequestViewV1.new(
          **values.except(:integration_link_events),
          trigger_event: event_reference_value(values[:trigger_event]),
          successful_integrations: values.fetch(:successful_integrations).map do |reference|
            Coordinator::Write::EventReference.new(reference)
          end,
          source: source_evidence_value(values.fetch(:source))
        )
      end

      def build_completion(attributes)
        values = symbolize(attributes)
        ReleaseSetCompletionViewV1.new(
          **values,
          source_event: event_reference_value(values[:source_event]),
          compensation_evidence: values.fetch(:compensation_evidence).map { compensation_evidence_value(_1) },
          source: source_evidence_value(values.fetch(:source))
        )
      end

      def event_reference_value(attributes)
        return unless attributes
        return attributes if attributes.is_a?(Coordinator::Write::EventReference)

        Coordinator::Write::EventReference.new(symbolize(attributes))
      end

      def integration_failure_value(attributes)
        return unless attributes

        Coordinator::Write::ReleaseSets::IntegrationFailureV2.new(
          **attributes,
          producer: Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(attributes.fetch(:producer))
        )
      end

      def verification_evidence_value(attributes)
        Coordinator::Write::ReleaseSets::VerificationEvidenceV2.new(
          **attributes,
          producer: Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(attributes.fetch(:producer)),
          findings: attributes.fetch(:findings).map { Coordinator::Write::ReleaseSets::VerificationFindingV1.new(_1) }
        )
      end

      def compensation_evidence_value(attributes)
        Coordinator::Write::ReleaseSets::CompensationEvidenceV2.new(
          **attributes.except(:source_event_id),
          integration_event: Coordinator::Write::EventReference.new(attributes.fetch(:integration_event)),
          producer: Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(attributes.fetch(:producer))
        )
      end

      def source_evidence(record)
        ReleaseSetSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.prepared_event)),
          actor: AttributedActorV1.new(symbolize(record.prepared_actor)),
          markers: record.prepared_markers,
          metadata: record.prepared_metadata,
          global_position: record.prepared_global_position,
          occurred_at: record.prepared_at_domain.utc.iso8601(6),
          persisted_at: record.prepared_at_store.utc.iso8601(6),
          causation_id: record.prepared_causation_id,
          correlation_id: record.prepared_correlation_id
        )
      end

      def source_evidence_value(attributes)
        ReleaseSetSourceEvidenceV1.new(
          **attributes,
          event: Coordinator::Write::EventReference.new(attributes.fetch(:event)),
          actor: AttributedActorV1.new(attributes.fetch(:actor))
        )
      end

      def symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array then value.map { symbolize(_1) }
        else value
        end
      end
    end
  end
end
