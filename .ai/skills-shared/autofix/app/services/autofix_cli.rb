# frozen_string_literal: true

class AutofixCli
  include ServiceObject

  arguments :cli_args

  def call
    raise ArgumentError, 'Autofix requires exactly one review comment URL' unless cli_args.length == 1

    comment = FetchReviewComment.call(url: cli_args.first)
    puts RenderReviewComment.call(comment: comment)
  end
end
