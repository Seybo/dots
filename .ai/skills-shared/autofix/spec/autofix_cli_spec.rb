# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe AutofixCli do
  let(:issues) { Database.connection[:reported_issues] }

  it 'stores a local decision and displays the next issue' do
    issue_id = store_issue('First issue.')
    next_id = store_issue('Second issue.')

    expect do
      described_class.call(cli_args: ['store-decision', issue_id.to_s, 'approved'])
    end.to output("Decision: approved\n\nIssue: #{next_id}\n\n> Second issue.\n").to_stdout

    expect(issues.where(id: issue_id).get(:decision)).to eq('approved')
  end

  it 'reports an empty queue after storing the last local decision' do
    issue_id = store_issue('Only issue.')

    expect do
      described_class.call(cli_args: ['store-decision', issue_id.to_s, 'skipped'])
    end.to output("Decision: skipped\n\nNo unresolved issues.\n").to_stdout
  end

  def store_issue(body)
    StoreIssue.call(project_path: '/project', source: 'local', body: body)
  end
end
