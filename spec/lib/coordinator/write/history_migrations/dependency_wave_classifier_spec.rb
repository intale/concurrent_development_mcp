# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::DependencyWaveClassifier do
  subject(:classifier) { described_class.new }

  it "places stream creation before definitions, relations, and terminal facts" do
    expect(classifier.call(target_event_type: "RepositoryRegistered", target_revision: 0)).to eq(0)
    expect(classifier.call(target_event_type: "RepositoryDisplayNameChanged", target_revision: 1)).to eq(1)
    expect(classifier.call(target_event_type: "WorkItemAddedToChangeSet", target_revision: 0)).to eq(2)
    expect(classifier.call(target_event_type: "WorkItemDependencyDeclared", target_revision: 1)).to eq(2)
    expect(classifier.call(target_event_type: "ChangeSetCompleted", target_revision: 1)).to eq(3)
  end

  it "never moves a later event in one target stream to an earlier wave" do
    expect(
      classifier.call(
        target_event_type: "ChangeSetDescriptionChanged",
        target_revision: 2,
        previous_wave: 3
      )
    ).to eq(3)
  end

  it "keeps intentions with execution facts so their Attempt is already projected" do
    expect(classifier.call(target_event_type: "ResourceWorkIntentionDeclared", target_revision: 0)).to eq(3)
    expect(classifier.call(target_event_type: "AttemptStarted", target_revision: 4)).to eq(3)
  end
end
