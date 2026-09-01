# frozen_string_literal: true

module GraphqlQueryLimitsSpec
  RSpec.describe "GraphQL query limits" do
    it "rejects queries deeper than the committed schema limit" do
      payload = execute(<<~GRAPHQL)
        query ExcessiveDepth {
          __schema {
            types {
              fields {
                type {
                  ofType {
                    ofType {
                      ofType {
                        ofType { name }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL

      expect(Coordinator::Web::Graphql::Schema.max_depth).to eq(8)
      expect(payload.dig("errors", 0, "message")).to match(/depth.+exceeds max depth/i)
      expect(payload["data"]).to be_nil
    end

    it "rejects queries more expensive than the committed schema limit" do
      selections = 40.times.map do |index|
        <<~GRAPHQL
          projects#{index}: projects(scope: "project:query-limits", first: 1) {
            nodes { id name scope }
            pageInfo { endCursor hasNextPage }
          }
        GRAPHQL
      end.join
      payload = execute("query ExcessiveComplexity { #{selections} }")

      expect(Coordinator::Web::Graphql::Schema.max_complexity).to eq(100)
      expect(payload.dig("errors", 0, "message")).to match(/complexity.+exceeds max complexity/i)
      expect(payload["data"]).to be_nil
    end

    def execute(query)
      graphql_session.post "/graphql", params: { query: }, as: :json
      expect(graphql_session.response.status).to eq(200), graphql_session.response.body
      graphql_session.response.parsed_body
    end

    def graphql_session
      @graphql_session ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
        session.host! "localhost"
      end
    end
  end
end
