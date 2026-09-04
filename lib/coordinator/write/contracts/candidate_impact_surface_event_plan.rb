# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateImpactSurfaceEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::SubmitCandidateImpactSurface))
        required(:surface_id).filled(:string)
      end

      rule(:plan, :command, :surface_id) do
        command = values[:command]
        surface_id = values[:surface_id]
        surface = command.surface
        expected = Events::CandidateImpactSurfaceDerivedV2.new(
          surface_id:,
          candidate_id: command.candidate_id,
          evidence_revision: 1,
          produces: surface.produces,
          consumes: surface.consumes,
          may_affect: surface.may_affect,
          assumes: surface.assumes
        )
        assignment = Events::CandidateImpactSurfaceAssignedV1.new(
          candidate_id: command.candidate_id,
          surface_id:
        )
        streams = StreamFactory.new
        plan = values[:plan]
        unless plan.events == [ expected, assignment ] &&
               plan.writes.map(&:stream) == [
                 streams.candidate_impact_surface(surface_id),
                 streams.candidate(command.candidate_id)
               ]
          key(:plan).failure("must preserve the exact surface derivation and Candidate assignment facts")
        end
      end
    end
  end
end
