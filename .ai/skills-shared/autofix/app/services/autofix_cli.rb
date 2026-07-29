# frozen_string_literal: true

class AutofixCli
  include ServiceObject

  arguments :cli_args

  def call
    raise ArgumentError, 'Autofix does not accept arguments' unless cli_args.empty?

    comment = FetchPullRequestComments.call.first
    puts RenderReviewComment.call(comment: comment)
  end
end
