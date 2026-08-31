# frozen_string_literal: true

class GraphqlController < ApplicationController
  def execute
    result = Coordinator::Web::Graphql::Schema.execute(
      params[:query],
      variables: prepare_variables(params[:variables]),
      operation_name: params[:operationName],
      context: {}
    )

    render json: result.to_h
  rescue JSON::ParserError => error
    render json: { errors: [ { message: error.message } ] }, status: :unprocessable_entity
  end

  private

  def prepare_variables(raw_variables)
    case raw_variables
    when String
      raw_variables.present? ? JSON.parse(raw_variables) : {}
    when Hash
      raw_variables
    when ActionController::Parameters
      raw_variables.to_unsafe_h
    when nil
      {}
    else
      raise JSON::ParserError, "variables must be a JSON object"
    end
  end
end
