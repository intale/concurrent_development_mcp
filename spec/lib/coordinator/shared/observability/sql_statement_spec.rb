# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Observability::SqlStatement do
  it "bounds operation names without putting caller-controlled SQL in a label" do
    expect(described_class.operation("  select * from repositories")).to eq("SELECT")
    expect(described_class.operation("WITH rows AS (SELECT 1) SELECT * FROM rows")).to eq("OTHER")
    expect(described_class.operation("private operation")).to eq("OTHER")
  end

  it "retains query structure while removing literal values and comments" do
    sql = "SELECT * FROM repositories WHERE name = 'private-name' AND count = 123 AND active = true -- private-comment"
    text = described_class.text(sql)
    expect(text).to include("SELECT * FROM repositories WHERE name = ? AND count = ? AND active = ?")
    expect(text).not_to match(/private|123|true/)
    expect(described_class.text("SELECT E'private-escaped\\\\value', B'101', X'AB', U&'private-unicode'")).not_to match(/private|101|AB/)
  end

  it "omits dollar-quoted statements, malformed statements and oversized input" do
    [ "SELECT $tag$private-first\nprivate-second$tag$", "SELECT $$private$$", "SELECT $é$private\nsecond$é$",
      "SELECT 'unterminated-private", "SELECT '#{'x' * 32768}'" ].each do |sql|
      expect(described_class.text(sql)).to be_nil
    end
    expect(described_class.text("SELECT * FROM repositories WHERE repository_id = $1")).to include("$?")
  end

  it "truncates only sanitized text, preserving UTF-8 and the size bound" do
    text = described_class.text("SELECT #{('name, ' * 500)} 'private-tail'")
    expect(text.length).to eq(2048)
    expect(text.encoding).to eq(Encoding::UTF_8)
    expect(text).not_to include("private-tail")
  end
end
