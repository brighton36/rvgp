class Sheet
  attr_accessor :title, :options

  MAX_COLUMNS = 26

  def initialize(title, grid, options = {})
    @title,  @options = title, options

    # Google offers this option in its GUI, but doesn't seem to support it via
    # the API. So, we can just do that ourselves:
    @grid = options[:switch_rows_columns] ? 
      0.upto(grid[0].length-1).collect{ |i| grid.collect{|row| row[i]} } :
      grid

    # This is a Google constraint:
    raise StandardError, "Too many columns. Max is %d, provided %d." % [
      MAX_COLUMNS, columns.length] if (columns.length > MAX_COLUMNS)
  end

  def columns; @grid[0]; end
  def rows; @grid[1...]; end
end

