# frozen_string_literal: true

module Coordinator::Mcp
  module Tasks
    module ResultSchemas
      module_function

      def created
        DryStructSchema.new.call(ResultV1::Created)
      end

      def detailed
        {
          oneOf: [ ResultV1::Working, ResultV1::WorkingWithMessage, ResultV1::Completed,
            ResultV1::Failed, ResultV1::Cancelled ].map { DryStructSchema.new.call(_1) }
        }
      end

      def acknowledgement
        DryStructSchema.new.call(ResultV1::Acknowledgement)
      end
    end
  end
end
