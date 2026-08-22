# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    module ResultV1
      class Base < Value
        attribute :taskId, Types::TaskId
        attribute :createdAt, Types::Timestamp
        attribute :lastUpdatedAt, Types::Timestamp
        attribute :ttlMs, Types::Nil
        attribute :pollIntervalMs, Types::Integer.constrained(eql: 500)
      end

      class CallToolResult < Value
        attribute :content, Types::Array.of(Types.Instance(Coordinator::Write::Tasks::TextContentV1))
        attribute :isError, Types::Strict::Bool
        attribute :structuredContent, Types.Instance(Coordinator::Write::Tasks::StructuredContentV1)
      end

      class Created < Base
        attribute :resultType, Types::String.constrained(eql: "task")
        attribute :status, Types::String.constrained(eql: "working")
      end

      class Working < Base
        attribute :resultType, Types::String.constrained(eql: "complete")
        attribute :status, Types::String.constrained(eql: "working")
      end

      class WorkingWithMessage < Working
        attribute :statusMessage, Types::String
      end

      class Completed < Base
        attribute :resultType, Types::String.constrained(eql: "complete")
        attribute :status, Types::String.constrained(eql: "completed")
        attribute :result, CallToolResult
      end

      class Failed < Base
        attribute :resultType, Types::String.constrained(eql: "complete")
        attribute :status, Types::String.constrained(eql: "failed")
        attribute :statusMessage, Types::String
        attribute :error, Types.Instance(Coordinator::Write::Tasks::JsonRpcErrorV1)
      end

      class Cancelled < Base
        attribute :resultType, Types::String.constrained(eql: "complete")
        attribute :status, Types::String.constrained(eql: "cancelled")
        attribute :statusMessage, Types::String
      end

      class Acknowledgement < Value
        attribute :resultType, Types::String.constrained(eql: "complete")
      end

      Detailed = Working | WorkingWithMessage | Completed | Failed | Cancelled
    end
  end
end
