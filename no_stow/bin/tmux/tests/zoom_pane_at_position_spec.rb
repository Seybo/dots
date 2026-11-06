# frozen_string_literal: true

require 'rspec'
load File.expand_path('../zoom-pane-at-position', __dir__)

RSpec.describe PanePositionZoom do
  def pane(pane_id, x, y)
    { 't' => 'p', 'I' => pane_id, 'x' => x, 'y' => y }
  end

  # Column-first tree traversal differs from the desired row-first shortcut order.
  let(:layout) do
    JSON.generate('V' => 2, 'L' => { 't' => 'v', 'c' => [
      { 't' => 'h', 'c' => [
        { 't' => 'v', 'c' => [pane('%17', 0, 0), pane('%48', 0, 24)] },
        { 't' => 'v', 'c' => [pane('%21', 75, 0), pane('%45', 75, 24)] }
      ] },
      pane('%50', 0, 48)
    ] })
  end

  describe '.pane_order' do
    it 'sorts five panes by top then left, not tree or ID order' do
      expect(described_class.pane_order(layout)).to eq(%w[%17 %21 %48 %45 %50])
    end

    it 'sorts coordinates numerically' do
      layout = JSON.generate('L' => { 't' => 'h', 'c' => [
        pane('%1', 100, 2), pane('%2', 20, 2), pane('%3', 0, 10)
      ] })
      expect(described_class.pane_order(layout)).to eq(%w[%2 %1 %3])
    end

    it 'handles a single pane' do
      expect(described_class.pane_order(JSON.generate('L' => pane('%7', 0, 0)))).to eq(['%7'])
    end
  end

  describe '.zoom_pane' do
    let(:status) { instance_double(Process::Status, success?: true) }

    before do
      allow(Open3).to receive(:capture2).and_return([layout, status])
      allow(described_class).to receive(:system).and_return(true)
    end

    it 'reads the unzoomed layout of the explicit window' do
      expect(Open3).to receive(:capture2).with(
        'tmux', 'display-message', '-p', '-t', '@11', '#{window_layout}' # rubocop:disable Lint/InterpolationCheck -- tmux format, not Ruby interpolation.
      ).and_return([layout, status])
      described_class.zoom_pane(2, '@11')
    end

    it 'selects the position-based pane and conditionally zooms in one command queue' do
      expect(described_class).to receive(:system).with(
        'tmux', 'select-pane', '-Z', '-t', '%21', ';',
        'if-shell', '-t', '%21', '-F', '#{!:#{window_zoomed_flag}}',
        'resize-pane -Z -t %21', exception: true
      )
      described_class.zoom_pane(2, '@11')
    end

    it 'does not select or change zoom for a missing position' do
      expect(described_class).not_to receive(:system)
      described_class.zoom_pane(6, '@11')
    end

    it 'does not select the last pane for position zero' do
      expect(described_class).not_to receive(:system)
      described_class.zoom_pane(0, '@11')
    end

    it 'does not select or change zoom when the layout query fails' do
      allow(status).to receive(:success?).and_return(false)
      expect(described_class).not_to receive(:system)
      expect { described_class.zoom_pane(1, '@11') }.to raise_error('tmux layout query failed')
    end
  end
end
