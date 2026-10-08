# frozen_string_literal: true

module Linear
  module Markdown
    module_function

    def parse(text)
      lines = text.lines
      lines.shift if lines.first&.start_with?('Feature:')
      start_index = lines.index { |line| line.chomp == '# Story details' }
      title = nil
      if start_index
        end_index = ((start_index + 1)...lines.length).find { |index| lines[index].start_with?('# ') } || lines.length
        name = lines[start_index...end_index].find { |line| line.start_with?('Name:') }
        title = name&.delete_prefix('Name:')&.strip
        lines.slice!(start_index...end_index)
      end
      result = { 'description' => lines.join.sub(/\A\s*\n/, '') }
      result['title'] = title unless title.nil? || title.empty?
      result
    end
  end
end
