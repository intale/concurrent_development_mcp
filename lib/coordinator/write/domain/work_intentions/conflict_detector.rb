# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module WorkIntentions
      class ConflictDetector
        def call(requests:, observations:, at:, ignored_intention_ids: [])
          observations.select do |observation|
            state = observation.state
            next false unless state.active_at?(at)
            next false if ignored_intention_ids.include?(state.intention_id)

            requests.any? do |request|
              resources_overlap?(request.resource, observation.resource) &&
                incompatible_modes?(request.prepared_target.target.mode, state.mode)
            end
          end.uniq { _1.state.intention_id }
        end

        def details(observations)
          {
            blockers: observations.map do |observation|
              state = observation.state
              resource = observation.resource
              {
                intention_id: state.intention_id,
                resource_id: state.resource_id,
                resource_kind: resource.kind,
                resource_path: resource.path,
                mode: state.mode,
                owner_agent_id: state.agent_id,
                owner_attempt_id: state.attempt_id,
                purpose: state.purpose,
                context: state.context,
                expires_at: state.expires_at,
                scope: {
                  repository_id: state.repository_id,
                  change_set_id: state.change_set_id,
                  work_item_id: state.work_item_id
                }
              }
            end
          }
        end

        private

        def incompatible_modes?(requested, current)
          requested == "exclusive" || current == "exclusive"
        end

        def resources_overlap?(requested, current)
          return true if requested.path == current.path

          (requested.kind == "directory" && current.path.start_with?("#{requested.path}/")) ||
            (current.kind == "directory" && requested.path.start_with?("#{current.path}/"))
        end
      end
    end
  end
end
