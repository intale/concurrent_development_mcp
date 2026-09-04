# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class MergeAuthorizationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::RequestMergeAuthorization))
        required(:evaluation).value(Types.Instance(MergeAuthorizations::EvaluationV1))
        required(:authorization_id).filled(:string)
      end

      rule(:plan, :command, :evaluation, :authorization_id) do
        decision = Domain::MergeAuthorizations::Decide.new.call(
          command: values[:command],
          evaluation: values[:evaluation],
          authorization_id: values[:authorization_id]
        )
        key(:plan).failure("must preserve the exact merge-authorization decision") unless decision.success? && decision.value! == values[:plan]
      end
    end
  end
end
