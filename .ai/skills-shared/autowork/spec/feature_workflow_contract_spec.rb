# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'Feature workflow contract' do
  let(:documents) do
    shared_root = File.expand_path('../..', __dir__)
    {
      featureit: File.read(File.join(shared_root, 'featureit/SKILL.md')),
      grillme: File.read(File.join(shared_root, 'grillme/SKILL.md')),
      grilling: File.read(File.join(shared_root, 'grilling/SKILL.md')),
      draftit: File.read(File.join(shared_root, 'draftit/SKILL.md')),
      taskit: File.read(File.join(shared_root, 'taskit/SKILL.md')),
      workit: File.read(File.join(shared_root, 'workit/SKILL.md')),
      autoimplement: File.read(File.join(shared_root, 'autowork/autoimplement/SKILL.md')),
      autofix: File.read(File.join(shared_root, 'autowork/autofix/SKILL.md')),
      sumit: File.read(File.join(shared_root, 'sumit/SKILL.md')),
      super_review: File.read(File.join(shared_root, 'super-review/SKILL.md')),
      addressit: File.read(File.join(shared_root, 'addressit/lib/addressit.rb')),
      load_task_context: File.read(File.join(shared_root, 'autowork/app/services/load_task_context.rb')),
      show_task_work_cycle: File.read(
        File.join(shared_root, 'autowork/autoimplement/app/services/show_task_work_cycle.rb')
      ),
      show_review_work_cycle: File.read(
        File.join(shared_root, 'autowork/autofix/app/services/show_work_cycle.rb')
      ),
      autoimplement_prompt: File.read(
        File.join(shared_root, 'autowork/autoimplement/app/prompts/work_cycle.md')
      ),
      autofix_prompt: File.read(File.join(shared_root, 'autowork/autofix/app/prompts/work_cycle.md')),
      resolution: File.read(File.join(shared_root, 'components/task-resolution.md'))
    }
  end

  def featureit
    documents.fetch(:featureit)
  end

  def grillme
    documents.fetch(:grillme)
  end

  def grilling
    documents.fetch(:grilling)
  end

  def draftit
    documents.fetch(:draftit)
  end

  def taskit
    documents.fetch(:taskit)
  end

  def workit
    documents.fetch(:workit)
  end

  def autoimplement
    documents.fetch(:autoimplement)
  end

  def sumit
    documents.fetch(:sumit)
  end

  def super_review
    documents.fetch(:super_review)
  end

  def addressit
    documents.fetch(:addressit)
  end

  def resolution
    documents.fetch(:resolution)
  end

  it 'defines optional env Feature identity and relative links once' do
    expect(resolution).to include('/Volumes/dev/_tasks/env/features/<feature-slug>.md')
    expect(resolution).to include('Feature: [<feature-slug>](../features/<feature-slug>.md)')
    expect(resolution).to include('# Drafts and tasks')
    expect(resolution).to match(/Task reference.*authoritative/im)
    expect(resolution).to match(/task-specific.*wins/im)
  end

  it 'researches a user-provided idea and creates one no-clobber Feature' do
    expect(featureit).to include('disable-model-invocation: true')
    expect(featureit).to include('/skill:featureit <feature-idea>')
    expect(featureit).to match(/require a non-empty natural-language Feature idea/i)
    expect(featureit).to match(/inspect relevant local code.*documentation/im)
    expect(featureit).to match(/official documentation or upstream source/i)
    expect(featureit).to match(/available web-search workflow/i)
    expect(featureit).to match(/existing tools or plugins with similar functionality/i)
    expect(featureit).to match(/must not already exist/i)
    expect(featureit).to match(/derive.*Feature slug/im)
  end

  it 'reports the research audit and hands the Feature to Grillme without splitting it' do
    expect(featureit).to match(/does not grill.*propose.*split.*create drafts/im)
    expect(featureit).to include('Local code and docs:')
    expect(featureit).to include('Official documentation:')
    expect(featureit).to include('Web search:')
    expect(featureit).to include('Comparable projects:')
    expect(featureit).to match(/explicit.*Not performed/im)
    expect(featureit).to match(/exact bare `grillme`/i)
    expect(featureit).to include('../grillme/SKILL.md')
    expect(featureit).to match(/one capability/i)
    expect(featureit).not_to include('Propose split to drafts?')
  end

  it 'offers one Draftit continuation from completed non-draft Grillme sessions' do
    expect(grillme).to match(/offer only `draftit`/i)
    expect(grillme).not_to include('../featureit/SKILL.md')
    expect(grillme).to match(/Feature slug.*Feature reference/im)
    expect(grillme).to match(%r{draftNN/task\.md.*taskit}im)
  end

  it 'keeps Draftit context-only and receives project and Feature state from the flow' do
    expect(draftit).to include('/draftit <context-reference-or-text>')
    expect(draftit).not_to include('/draftit <project>')
    expect(draftit).not_to include('feature: <feature-slug>')
    expect(draftit).not_to include('epic: <id>')
    expect(draftit).to include('Feature: [<feature-slug>](../features/<feature-slug>.md)')
    expect(draftit).not_to match(/Featureit.*batch/im)
    expect(draftit).to match(/Grillme.*handoff.*Feature/im)
    expect(draftit).to match(/current registered checkout/im)
    expect(draftit).to match(/append.*ordered.*inventory/im)
  end

  it 'grills one Feature capability while preserving the final inventory' do
    expect(grilling).to match(/grill exactly one capability per session/i)
    expect(grilling).to match(/preserve unrelated research and unresolved questions/i)
    expect(grilling).to match(/Deferred decisions.*immediately before.*Drafts and tasks/im)
  end

  it 'defers Shortcut epic selection from Draftit to Taskit' do
    expect(taskit).to match(/Name:.*without.*Epic:.*ask.*epic.*exact `local`/im)
    expect(taskit).to match(/after.*Shortcut story.*add.*Epic:/im)
  end

  it 'preserves membership and replaces the inventory link after Taskit conversion' do
    expect(taskit).to include('Feature: [<feature-slug>](../features/<feature-slug>.md)')
    expect(taskit).to match(/Task reference.*authoritative/im)
    expect(taskit).to match(/do not scan.*Feature files/im)
    expect(taskit).to include('- [draftNN](../draftNN/task.md)')
    expect(taskit).to include('- [<task-folder>](../<task-folder>/task.md)')
    expect(taskit).to match(/after.*successful.*rename.*replace/im)
    expect(taskit).to match(/do not modify.*Feature reference/im)
  end

  it 'ignores Feature metadata when deriving or displaying Task names' do
    expect(taskit).to match(/ignore.*Feature metadata line/im)
    expect(workit).to match(/ignore.*Feature metadata line/im)
    expect(autoimplement).to match(/ignore.*Feature metadata line/im)
    expect(taskit).to match(/unfeatured.*unchanged/im)
  end

  it 'loads linked Feature context in interactive Task consumers' do
    expect(resolution).to match(/read.*complete Feature file.*before.*task\.md/im)
    expect(grilling).to match(/load the linked Feature before `task\.md`/i)
    expect(workit).to match(/load the linked Feature before `task\.md`/i)
    expect(sumit).to match(/load the linked Feature before `task\.md`/i)
    expect(super_review).to match(/load the linked Feature before `task\.md`/i)
    expect(addressit.scan('read the linked Feature file before task.md').length).to eq(3)
  end

  it 'passes transient Feature context to autonomous Work Cycles' do
    expect(documents.fetch(:load_task_context)).to include('feature_path:', 'feature_text:')
    expect(documents.fetch(:show_task_work_cycle)).to include('feature_path:', 'feature_text:')
    expect(documents.fetch(:show_review_work_cycle)).to include('task_path:', 'feature_path:', 'feature_text:')
    expect(autoimplement).to include('returned `feature_path` and `feature_text`')
    expect(documents.fetch(:autofix)).to include('returned `task_path`, `feature_path`, and `feature_text`')

    %i[autoimplement_prompt autofix_prompt].each do |name|
      prompt = documents.fetch(name)
      expect(prompt).to include('returned `feature_path` and `feature_text`')
      expect(prompt).to include('do not treat the Feature inventory as requirements')
      expect(prompt).to include('do not perform a Feature lookup')
    end
  end
end
