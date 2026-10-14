# frozen_string_literal: true

RSpec.describe Coordinator::Read::Repositories::CoordContexts, :read_model do
  subject(:repository) { described_class.new }

  it "serves factory-backed context and paged Attempt history without write-side or subscription state" do
    context = create(:coordinator_read_coord_context)
    create(:coordinator_read_coord_context_scope, scope_kind: "change_set", scope_id: context.change_set_id, change_set_id: context.change_set_id)
    first = create(:coordinator_read_attempt_history, change_set_id: context.change_set_id, work_item_id: "W-page", authorized_global_position: 10)
    second = create(:coordinator_read_attempt_history, change_set_id: context.change_set_id, work_item_id: "W-page", authorized_global_position: 20)
    snapshot = repository.resolve(scope_kind: "change_set", scope_id: context.change_set_id)
    expect(snapshot.state.change_set.change_set_id).to eq(context.change_set_id)
    first_page = repository.attempt_page(work_item_id: "W-page", after_authorized_global_position: nil, limit: 1)
    expect(first_page).to have_attributes(has_more: true, next_authorized_global_position: 10)
    expect(first_page.items.sole.attempt_id).to eq(first.attempt_id)
    last_page = repository.attempt_page(work_item_id: "W-page", after_authorized_global_position: 10, limit: 1)
    expect(last_page.items.sole.attempt_id).to eq(second.attempt_id)
    expect(last_page.has_more).to be(false)
  end
end
