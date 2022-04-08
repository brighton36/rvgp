class Sheet
  attr_accessor :title, :options

  MAX_COLUMNS = 26

  def initialize(title, grid, options = {})
    @title,  @options, @grid = title, options, grid

    # This is a Google constraint:
    raise StandardError, "Too many columns. Max is %d, provided %d." % [
      MAX_COLUMNS, columns.length] if (columns.length > MAX_COLUMNS)
  end

  def columns; @grid[0]; end
  def rows; @grid[1...]; end
end

