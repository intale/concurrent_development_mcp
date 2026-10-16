# frozen_string_literal: true

Given("twenty one projected Projects are available for browser discovery") do
  @browser_catalog_scope = "project:test/ui-journey-21"
  21.times do |index|
    number = index + 1
    scope = format("project:test/ui-journey-%02d", number)
    FactoryBot.create(
      :coordinator_read_repository,
      repository_key: format("ui-journey-%02d", number),
      scope:,
      display_name: format("UI journey %02d", number)
    )
  end
end

When("the person pages and filters the live Project catalog") do
  browser_resize_to(1_440, 1_000)
  visit "/projects"
  browser_assert_table!
  assert_selector("table tbody tr", count: 20)
  assert_selector("table tbody th[scope='row']", count: 20)

  click_button "Next page"
  assert_text(/Page 2 · \d+ Projects?/)
  click_button "Previous page"
  assert_text "Page 1 · 20 Projects"

  fill_in "Search", with: @browser_catalog_scope
  click_button "Apply search"
  assert_text "UI journey 21"
  assert_selector("table tbody tr", text: "UI journey 21", count: 1)

  page.execute_script(<<~JAVASCRIPT)
    window.history.pushState({}, "", `${window.location.pathname}${window.location.search}&after=invalid-cursor`);
    window.dispatchEvent(new PopStateEvent("popstate"));
  JAVASCRIPT
end

Then("a real cursor failure is bounded and Back restores the prior Project page") do
  assert_text "Projects could not be loaded"
  assert_text "project cursor is invalid"
  page.go_back
  assert_text "UI journey 21"
end

Then("the selected Project opens at its readable exact-scope route") do
  click_link "UI journey 21", exact: true
  @browser_project_path = page.current_path
  route_scope = CGI.unescape(URI.parse(@browser_project_path).path.split("/")[2])
  assert_acceptance_equal(@browser_catalog_scope, route_scope, "Readable exact-scope route")
  assert_acceptance(!page.current_url.include?("returnTo="), "Project route added a returnTo query")
  assert_selector("h1", text: "UI journey 21", exact_text: true)
  assert_acceptance(
    browser_focused_text == "UI journey 21",
    "Project heading did not receive focus"
  )
end

Then("browser Back and refresh preserve the selected Project context") do
  page.go_back
  assert_acceptance_equal(@browser_catalog_scope, find_field("Search").value, "Restored Project search")
  assert_text "UI journey 21"

  click_link "UI journey 21", exact: true
  assert_acceptance(page.current_path == @browser_project_path, "Project route changed after Back")
  page.refresh
  assert_selector("h1", text: "UI journey 21", exact_text: true)
  assert_acceptance(page.current_path == @browser_project_path, "Project deep link changed after refresh")
end

Then("the Project remains operable at 390 and 320 pixels") do
  browser_resize_to(390, 844)
  browser_assert_no_document_overflow

  toggle = find("button[aria-label='Toggle navigation']", visible: :all)
  assert_acceptance(toggle.visible?, "Compact navigation toggle is not visible")
  toggle.click
  assert_selector("button[aria-label='Toggle navigation'][aria-expanded='true']")
  page.driver.browser.switch_to.active_element.send_keys(:escape)
  assert_selector("button[aria-label='Toggle navigation'][aria-expanded='false']")
  assert_acceptance(browser_focused_label == "Toggle navigation", "Navigation focus was not restored")

  browser_resize_to(320, 800)
  browser_assert_no_document_overflow
end

Given("representative projected coordination facts share one Project") do
  step "projected dashboard rows contain a running WorkItem with a Candidate checkpoint"
  context = Coordinator::Read::CoordContext.find("CS-detail")
  document = context.document.deep_dup
  document["work_item_ids"] << "W-consumer"
  document["work_items"] << dashboard_work_item_row(
    "W-consumer",
    "planned",
    change_set_key: "detail"
  )
  document["dependencies"] = [
    {
      "dependency_id" => "D-browser-detail",
      "producer_work_item_id" => "W-detail",
      "consumer_work_item_id" => "W-consumer",
      "dependency_kind" => "requires_completion",
      "required_output" => nil,
      "source_event" => nil,
      "declared_at" => "2026-08-31T12:00:00.000000Z",
      "satisfied_at" => nil
    }
  ]
  context.update!(document:)
end

When("the person follows the live Coordination routes") do
  browser_open_project(@coordination_dashboard_project_ref)
  click_link "Change sets", exact: true
  assert_selector("h2", text: "ChangeSets", exact_text: true)
  browser_assert_latest_update_sort

  browser_click_row("CS-detail")
  @coordination_browser_details = [ browser_record_refreshable_detail("ChangeSet detail") ]
  click_link "Back to ChangeSets"

  click_link "Work items", exact: true
  browser_click_row("W-detail")
  @coordination_browser_details << browser_record_refreshable_detail("WorkItem detail")
  assert_text "CAND-detail"
  click_link "Back to WorkItems"

  click_link "Dependencies", exact: true
  browser_assert_latest_update_sort
  browser_click_row("D-browser-detail")
  @coordination_browser_details << browser_record_refreshable_detail("Dependency detail")
end

Then("each coordination detail is focused and independently refreshable") do
  browser_assert_detail_records(@coordination_browser_details, expected_count: 3)
end

When("the person follows the live Resource routes") do
  browser_open_project(@resource_browser_project_ref)
  click_link "Resources", exact: true
  assert_selector("h2", text: "Resource inventory", exact_text: true)
  browser_assert_latest_update_sort

  browser_click_row("app/models/first.rb")
  @resource_browser_details = [ browser_record_refreshable_detail("Resource detail") ]
  click_link "Back to Resource inventory"
  assert_selector("h2", text: "Resource inventory", exact_text: true, wait: 10)

  click_link "Work intentions", exact: true
  browser_assert_latest_update_sort
  browser_click_row("app/models/first.rb")
  @resource_browser_details << browser_record_refreshable_detail("Resource work-intention detail")
end

Then("Resource and work-intention details retain predictable Back routes") do
  browser_assert_detail_records(@resource_browser_details, expected_count: 2)
  assert_selector("a", text: "Back to active work intentions", exact_text: true)
end

When("the person follows the live Knowledge routes") do
  browser_open_project(@knowledge_browser_project_ref)
  click_link "Skills", exact: true
  assert_selector("h2", text: "Skills", exact_text: true)
  browser_assert_latest_update_sort

  browser_click_row("event-modeling")
  @knowledge_browser_details = [ browser_record_refreshable_detail("Skill detail") ]
  assert_text "Current instructions"
  assert_no_text "Obsolete instructions"

  click_link "references/current.md", exact: true
  @knowledge_browser_details << browser_record_refreshable_detail("Skill asset")
  click_link "Back to Skill"
  click_link "Back to Skills"
  assert_selector("table tbody tr", text: "event-modeling", wait: 10)
  assert_acceptance(!page.current_url.include?("returnTo="), "Skill Back route added a returnTo query")

  click_link "Development artifacts", exact: true
  browser_assert_latest_update_sort
  browser_click_row("Parent README")
  @knowledge_browser_details << browser_record_refreshable_detail("Artifact detail")
  click_link "View 1 relationships"
  @knowledge_browser_details << browser_record_refreshable_detail("Artifact relationships")
  assert_text "Child guide"
  click_link "Child guide", exact: true
  assert_selector("h2", text: "Artifact detail", exact_text: true)
end

Then("current Skill and Artifact relationship details are independently addressable") do
  browser_assert_detail_records(@knowledge_browser_details, expected_count: 4)
  assert_text "Child guide"
end

Given("representative projected Governance facts share one Project") do
  step "projected governance rows span two Project members and an unrelated Project"
  FactoryBot.create(
    :coordinator_read_decision_definition,
    decision_id: governance_decision_id,
    repository_id: @governance_browser_repository_id,
    topic_id: "testing.framework"
  )
end

When("the person follows the live Governance routes") do
  browser_open_project(@governance_browser_project_ref)
  click_link "Decisions", exact: true
  assert_selector("h2", text: "Decisions", exact_text: true)
  browser_assert_latest_update_sort

  @governance_browser_details = []
  browser_click_row(governance_decision_id)
  @governance_browser_details << browser_record_refreshable_detail("Decision detail")
  click_link "Back to Decisions", match: :first

  click_link "Guidance", exact: true
  browser_assert_latest_update_sort
  browser_click_row(governance_message_id)
  @governance_browser_details << browser_record_refreshable_detail("Guidance detail")
  click_link "Back to Guidance", match: :first

  click_link "Agent choices", exact: true
  browser_assert_latest_update_sort
  browser_click_row(governance_choice_id)
  @governance_browser_details << browser_record_refreshable_detail("AgentChoice detail")
  click_link "Back to AgentChoices", match: :first

  click_link "Decision impacts", exact: true
  browser_assert_latest_update_sort
  browser_click_row(governance_impact_id)
  @governance_browser_details << browser_record_refreshable_detail("Decision impact detail")
end

Then("Decision Guidance AgentChoice and impact details stay inside the Project") do
  browser_assert_detail_records(@governance_browser_details, expected_count: 4)
  assert_acceptance(
    @governance_browser_details.all? { _1.fetch(:path).start_with?("/projects/") },
    "A Governance detail escaped the Project route"
  )
end

When("the person follows the live Delivery routes") do
  browser_open_project(@delivery_project_ref)
  click_link "Checkpoints", exact: true
  assert_selector("h2", text: "Candidate checkpoints", exact_text: true)

  @delivery_browser_details = []
  browser_click_row(@delivery_detail_candidate.candidate_id)
  @delivery_browser_details << browser_record_refreshable_detail("Candidate checkpoint detail")
  click_link "Back to Candidates"

  click_link "Verification", exact: true
  browser_click_row(@delivery_obligation.obligation_id)
  @delivery_browser_details << browser_record_refreshable_detail("Verification obligation detail")
  click_link "Back to Obligations"

  click_link "Merge snapshots", exact: true
  browser_click_row("MS-cucumber-delivery")
  @delivery_browser_details << browser_record_refreshable_detail("Merge snapshot detail")
  click_link "Back to Merge snapshots"

  click_link "Release sets", exact: true
  browser_click_row("RS-cucumber-delivery")
  @delivery_browser_details << browser_record_refreshable_detail("ReleaseSet detail")
end

Then("Candidate obligation merge and ReleaseSet details stay independently addressable") do
  browser_assert_detail_records(@delivery_browser_details, expected_count: 4)
end

Given("projected global audit and operation facts are available") do
  global_skill_scope = "project:test/ui-global-skill"
  FactoryBot.create(
    :coordinator_read_repository,
    repository_key: "ui-global-skill",
    scope: global_skill_scope,
    display_name: "UI global Skill"
  )
  @browser_command_id = "adj.20260826.candidate.1.submit.with-a-long-coordination-identity"
  FactoryBot.create(
    :coordinator_read_command_receipt,
    command_id: @browser_command_id,
    tool_name: "candidate_submit"
  )
  @browser_batch = FactoryBot.create(
    :coordinator_read_operation_batch,
    status: "completed",
    succeeded_count: 2,
    rejected_count: 0
  )
  2.times do |index|
    item = FactoryBot.create(
      :coordinator_read_operation_batch_item,
      operation_batch: @browser_batch,
      item_index: index
    )
    FactoryBot.create(
      :coordinator_read_operation_batch_outcome,
      operation_batch: @browser_batch,
      item_index: index,
      command_id: item.command_id
    )
  end
  @browser_skill = FactoryBot.create(
    :coordinator_read_skill,
    name: "browser-gfm",
    scope: global_skill_scope
  )
  FactoryBot.create(
    :coordinator_read_skill_revision,
    skill: @browser_skill,
    description: "A globally discoverable Skill",
    instructions: "Use the linked GFM reference.",
    asset_count: 1
  )
  FactoryBot.create(
    :coordinator_read_skill_asset,
    skill: @browser_skill,
    path: "references/status.md",
    media_type: "text/markdown",
    content_text: "| State | Owner |\n| --- | --- |\n| ready | agent |\n\n- [x] verified\n\n~~obsolete~~\n\n<script>alert('unsafe')</script>"
  )
end

When("the person follows the live global routes") do
  browser_resize_to(1_440, 1_000)
  visit "/projects"
  click_link "All skills", exact: true
  assert_selector("h1", text: "Skills", exact_text: true)
  browser_assert_latest_update_sort
  fill_in "Exact Project scope", with: @browser_skill.scope
  fill_in "Exact Skill name", with: @browser_skill.name
  click_button "Apply"
  assert_selector("table tbody tr", text: @browser_skill.name, count: 1)
  select "Oldest first", from: "Latest update"
  assert_current_path(/sort=OLDEST_FIRST/, ignore_query: false)
  page.refresh
  assert_selector("table tbody tr", text: @browser_skill.name, count: 1)
  browser_click_row(@browser_skill.name)
  @global_skill_details = [ browser_record_refreshable_detail("Skill detail", selector: "h1") ]
  click_link "references/status.md", exact: true
  @global_skill_details << browser_record_refreshable_detail("Skill asset", selector: "h1")
  @global_skill_gfm = {
    table: page.has_css?("table.table.table-striped"),
    task: page.has_css?("input[type='checkbox'][checked][disabled]"),
    deleted: page.has_css?("del", text: "obsolete"),
    script: page.has_css?("script", text: "unsafe", visible: :all)
  }
  click_link "Back to Skill"
  click_link "Back to Skills"
  assert_selector("table tbody tr", text: @browser_skill.name, count: 1)
  assert_acceptance(page.current_url.include?("sort=OLDEST_FIRST"), "Skill list filters were not preserved")
  assert_acceptance(!page.current_url.include?("returnTo="), "Skill Back route added a returnTo query")

  click_link "Command receipts", exact: true
  assert_selector("h1", text: "Command receipts", exact_text: true)
  @browser_receipt_row = find("table tbody tr", text: @browser_command_id)

  @browser_receipt_layout = page.evaluate_script(<<~JAVASCRIPT, @browser_receipt_row)
    (() => {
      const row = arguments[0];
      const firstCell = row.querySelector("th, td");
      const statusBadge = row.querySelector(".badge");
      const cell = firstCell.getBoundingClientRect();
      const identityNode = firstCell.querySelector("a, code") || firstCell;
      const identity = identityNode.getBoundingClientRect();
      const badge = statusBadge.getBoundingClientRect();
      return {
        identityWithinFirstCell: identity.left >= cell.left && identity.right <= cell.right,
        statusInSeparateCell: statusBadge.parentElement !== firstCell,
        identityDoesNotOverlapStatus: identity.right <= badge.left || badge.right <= identity.left || identity.bottom <= badge.top || badge.bottom <= identity.top
      };
    })()
  JAVASCRIPT

  @global_browser_details = []
  @browser_receipt_row.find("a", match: :first).click
  @browser_receipt_detail_layout = page.evaluate_script(<<~JAVASCRIPT)
    (() => {
      const header = document.querySelector("article .card-header").getBoundingClientRect();
      const identity = document.querySelector("article .card-header code").getBoundingClientRect();
      const badge = document.querySelector("article .card-header .badge").getBoundingClientRect();
      return {
        identityWithinHeader: identity.left >= header.left && identity.right <= header.right,
        identityBelowBadge: identity.top >= badge.bottom,
        identityHasReadableWidth: identity.width >= 300
      };
    })()
  JAVASCRIPT
  @global_browser_details << browser_record_refreshable_detail("Command receipt", selector: "h1")
  click_link "Back to receipts", match: :first

  click_link "Operation batches", exact: true
  assert_selector("h1", text: "Operation batches", exact_text: true)
  browser_click_row(@browser_batch.batch_id)
  @global_browser_details << browser_record_refreshable_detail("Operation batch", selector: "h1")
end

Then("global Skills remain filterable and render safe GFM on focused pages") do
  browser_assert_detail_records(@global_skill_details, expected_count: 2)
  assert_acceptance(@global_skill_gfm.fetch(:table), "GFM table was not rendered")
  assert_acceptance(@global_skill_gfm.fetch(:task), "GFM task-list checkbox was not rendered")
  assert_acceptance(@global_skill_gfm.fetch(:deleted), "GFM strikethrough was not rendered")
  assert_acceptance(!@global_skill_gfm.fetch(:script), "Unsafe Skill asset HTML was rendered")
end

Then("the long command identity does not collide with its tool or status") do
  assert_acceptance(@browser_receipt_layout.fetch("identityWithinFirstCell"), "Command identity escaped its table identity cell")
  assert_acceptance(@browser_receipt_layout.fetch("statusInSeparateCell"), "Command status was not displayed in a separate table cell")
  assert_acceptance(@browser_receipt_layout.fetch("identityDoesNotOverlapStatus"), "Command identity collided with the status")
  assert_acceptance(@browser_receipt_detail_layout.fetch("identityWithinHeader"), "Detail identity escaped its card header")
  assert_acceptance(@browser_receipt_detail_layout.fetch("identityBelowBadge"), "Detail identity collided with the status")
  assert_acceptance(@browser_receipt_detail_layout.fetch("identityHasReadableWidth"), "Detail identity was squeezed below readable width")
end

Then("receipt and batch details have predictable Back routes") do
  browser_assert_detail_records(@global_browser_details, expected_count: 2)
  assert_selector("a", text: "Back to batches", exact_text: true)
end

def browser_open_project(project_ref)
  browser_resize_to(1_440, 1_000)
  visit "/projects/#{browser_route_segment(project_ref)}"
  assert_selector("h1", wait: 10)
end

def browser_route_segment(value)
  ERB::Util.url_encode(value).gsub("+", "%20").gsub("%3A", ":")
end

def browser_resize_to(width, height)
  page.current_window.resize_to(width, height)
  browser = page.driver.browser
  browser.bidi.send_cmd(
    "browsingContext.setViewport",
    context: browser.window_handle,
    viewport: { width:, height: }
  )
  assert_acceptance_equal(width, page.evaluate_script("window.innerWidth"), "Actual browser viewport width")
end

def browser_click_row(identity)
  browser_assert_table!
  row = find("table tbody tr", text: identity, match: :first, wait: 10)
  row.find("a", match: :first).click
end

def browser_assert_table!
  assert_selector("table thead tr th[scope='col']", minimum: 1, wait: 10)
  assert_selector("table tbody tr th[scope='row']", minimum: 1, wait: 10)
  assert_no_selector("main > article")
end

def browser_assert_latest_update_sort(value = "NEWEST_FIRST")
  assert_acceptance_equal(value, find_field("Latest update").value, "Latest update sort")
end

def browser_record_refreshable_detail(heading, selector: "h2")
  assert_selector(selector, text: heading, exact_text: true, wait: 10)
  path = page.current_path
  focused = browser_focused_text == heading
  page.refresh
  assert_selector(selector, text: heading, exact_text: true, wait: 10)
  {
    path:,
    focused:,
    refresh_path: page.current_path,
    refresh_focused: browser_focused_text == heading
  }
end

def browser_assert_detail_records(records, expected_count:)
  assert_acceptance_equal(expected_count, records.length, "Focused browser detail count")
  assert_acceptance_equal(records.length, records.map { _1.fetch(:path) }.uniq.length, "Unique detail routes")
  records.each do |record|
    assert_acceptance(record.fetch(:focused), "Detail heading did not receive focus at #{record.fetch(:path)}")
    assert_acceptance_equal(record.fetch(:path), record.fetch(:refresh_path), "Deep-link refresh path")
    assert_acceptance(record.fetch(:refresh_focused), "Refreshed detail heading did not receive focus")
  end
end

def browser_focused_text
  page.evaluate_script("document.activeElement ? document.activeElement.textContent.trim() : null")
end

def browser_focused_label
  page.evaluate_script("document.activeElement ? document.activeElement.getAttribute('aria-label') : null")
end

def browser_assert_no_document_overflow
  dimensions = page.evaluate_script(<<~JAVASCRIPT)
    ({ width: window.innerWidth, scrollWidth: document.documentElement.scrollWidth });
  JAVASCRIPT
  assert_acceptance(
    dimensions.fetch("scrollWidth") <= dimensions.fetch("width"),
    "Document overflowed at #{dimensions.fetch('width')}px"
  )
end
