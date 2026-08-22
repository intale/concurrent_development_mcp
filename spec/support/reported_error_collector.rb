# frozen_string_literal: true

class ReportedErrorCollector
  attr_reader :errors

  def initialize
    @errors = []
  end

  def report(error, **)
    @errors << error
  end
end
