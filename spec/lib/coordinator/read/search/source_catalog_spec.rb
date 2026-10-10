# frozen_string_literal: true

RSpec.describe Coordinator::Read::Search::SourceCatalog do
  it "routes every repeated raw-value selector through the atomic indexed value table" do
    Coordinator::Read::Search::FieldCatalog::FIELDS.each_value do |field|
      next unless field.values != "scalar" || field.path.include?("*") || field.entity_type == "work_item"

      described_class.new.call(field).each do |source|
        expect(source).to have_attributes(multiple_values: true, value: "sv.value"), field.selector
        expect(source.from).to include("JOIN coordinator_search_values sv"), field.selector
      end
    end
  end
end
