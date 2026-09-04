# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class CandidateObligationProcessSource < Dry::Validation::Contract
      ALLOWED = {
        "DecisionPartitionAdvanced" => [ "HumanGuidance", "DecisionPartition" ],
        "DecisionAddedToPartition" => [ "HumanGuidance", "DecisionPartition" ],
        "DecisionRemovedFromPartition" => [ "HumanGuidance", "DecisionPartition" ],
        "CandidateImpactSurfaceAssigned" => [ "DevelopmentIntegration", "Candidate" ],
        "CandidateImpactRegistrySweepStarted" => [ "DevelopmentIntegration", "CandidateImpactRegistrySweep" ],
        "CandidateImpactRegistrySweepProgressed" => [ "DevelopmentIntegration", "CandidateImpactRegistrySweep" ],
        "CandidateImpactPairScanStarted" => [ "DevelopmentIntegration", "CandidateImpactPairScan" ],
        "CandidateImpactPairScanProgressed" => [ "DevelopmentIntegration", "CandidateImpactPairScan" ]
      }.freeze

      params do
        required(:source).value(Types.Instance(CandidateObligations::SourceV1))
      end

      rule(:source) do
        source = values[:source]
        expected_stream = ALLOWED[source.reference.type]
        valid = expected_stream &&
                [ source.reference.stream_context, source.reference.stream_name ] == expected_stream &&
                source.payload.class.event_type == source.reference.type
        key(:source).failure("must be an allowed exact Candidate-obligation process source") unless valid
      end
    end
  end
end
