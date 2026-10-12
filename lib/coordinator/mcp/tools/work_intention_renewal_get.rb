# frozen_string_literal: true

module Coordinator::Mcp
  module Tools
    class WorkIntentionRenewalGet < QueryTool
      tool_name "work_intention_renewal_get"
      title "Inspect work-intention renewal progress"
      description "Read latest available renewal Saga progress using the returned task_id or a previously observed renewal_id; provide exactly one. Members commit independently; failure preserves completed renewals. Task polling is authoritative for completion. A stale progress projection is still served."
      input_schema Schemas.object_schema(properties: { renewal_id: Schemas.uuid_v7, task_id: Schemas.uuid_v7 }, required: []).merge(
        oneOf: [ { required: [ "renewal_id" ] }, { required: [ "task_id" ] } ])
      query "queries.work_intention_renewal_get"
    end
  end
end
