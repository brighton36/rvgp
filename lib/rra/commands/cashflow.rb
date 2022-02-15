require_relative '../report_viewer'
require_relative '../dashboard'

class RRA::Commands::Cashflow < RRA::CommandBase
  accepts_options OPTION_ALL, OPTION_LIST, [:date, :d, {has_value: 'DATE'}]

  class Target < RRA::CommandBase::TargetBase
    def self.all
      RRA::Commands::Cashflow.reports_by_targetname.keys.collect{|s| self.new s}
    end
  end

  def initialize(*args)
    super *args
    
    options[:date] = Date.strptime options[:date] if options.has_key? :date

    minimum_width = RRA::Dashboard.table_width_given_column_widths(column_widths[0..1])

    @errors << I18n.t( 'commands.cashflow.errors.screen_too_small', 
      screen_width: TTY::Screen.width, minimum_width: minimum_width
      ) unless TTY::Screen.width > minimum_width
  end

  def execute!
    puts dashboards.collect{ |dashboard|
      dashboard.to_s column_widths: column_widths[0...show_columns], 
        rows_ordered_by: lambda{|row| 
          series, data = row[0], row[1..]
          # Sort by the series type [Expenses/Income/etc], then by 'consistency',
          # then by total amount
          [series.split(':')[1], data.count(&:nil?), data.compact.sum*-1]
        },
        # Hide rows without any data
        show_row: lambda{|row| !row[1..].all?(&:nil?) }  
    }.join("\n\n")
  end

  private

  def dashboards
    @dashboards ||= targets.collect{ |target| 
      RRA::Dashboard.new target.name, 
        RRA::ReportViewer.new(
          self.class.reports_by_targetname[target.name], 
          store_cell: lambda{|cell| (cell) ? 
            RRA::Journal::Commodity.from_symbol_and_amount('$', cell) : cell 
          },
          select_columns: lambda{|col, column| 
            if options.has_key?(:date)
              Date.strptime(col, '%b-%y') <= options[:date]
            else
              column.any?{|cell| !cell.nil?}
            end
          }
        ), {
        pastel: RRA.pastel,
        series_column_name: I18n.t('commands.cashflow.account'),
        format_data_cell: lambda{|cell| 
          (cell) ? cell.to_s(commatize: true, precision:2) : nil
        },
        columns_ordered_by: lambda{|a, b| 
          [b, a].collect{|d| Date.strptime d, '%b-%y'}.reduce :<=>
        },
        summaries: [
          { 
            label: I18n.t('commands.cashflow.expenses'), 
            prettify: lambda{|row| 
              [RRA.pastel.bold(row[0])]+row[1..].collect{|s| RRA.pastel.red(s) } 
             }, 
            contents: lambda{|series, data| sum_column 'Expenses', series, data } 
          },
          { 
            label: I18n.t('commands.cashflow.income'),
            prettify: lambda{|row| 
              [RRA.pastel.bold(row[0])]+row[1..].collect{|s| RRA.pastel.green(s) } 
            }, 
            contents: lambda{|series, data| sum_column 'Income', series, data } 
          },
          { 
            label: I18n.t('commands.cashflow.cash_flow'), 
            prettify: lambda{|row| 
             [RRA.pastel.bold(row[0])]+row[1..].collect{|cell| 
               /\$[ ]*\-/.match(cell) ? RRA.pastel.red(cell) : RRA.pastel.green(cell) } 
            }, 
            contents: lambda{|series, data|
             %w(Expenses Income).collect{|s| sum_column s, series, data }.sum.invert!
            } 
          }
        ]
      }
    }
  end

  def column_widths
    # We want every table being displayed, to have the same column widths.
    # probably we can move most of this code into a Dashboard class method. But, no
    # rush on that.
    @column_widths ||= dashboards.collect(&:column_data_widths)\
      .inject([]) { |sum, widths|
        widths.collect.with_index{|w, i| (sum[i].nil? or sum[i] < w) ? w : sum[i] }
      }
  end

  def show_columns
    return @show_columns if @show_columns
    # Now let's calculate how many columns fit on screen:
    @show_columns = 0
    0.upto(column_widths.length-1) do |i|
      break if RRA::Dashboard.table_width_given_column_widths(column_widths[0..i]) >
        TTY::Screen.width
      @show_columns += 1 
    end
    @show_columns
  end


  def sum_column(for_series, series, data)
    # NOTE: This for_series determination is a bit 'magic' and specific to our 
    # current accounting categorization taxonomy
    0.upto(series.length-1).collect{|i|
      (series[i].split(':')[1] == for_series and data[i]) ?
        data[i] : '$0.00'.to_commodity
    }.compact.sum
  end

  def self.cashflow_report_files
    Dir.glob RRA.app.config.build_path('reports/*-cashflow-*.csv')
  end

  def self.reports_by_targetname
    @reports_by_targetname ||= cashflow_report_files.inject(Hash.new){|sum, file|  
      raise I18n.t('commands.cashflow.errors.unrecognized_path', 
        file: file) unless /([^\-]+)\.csv\Z/.match file

      tablename = $1.capitalize

      sum[tablename] ||= Array.new
      sum[tablename] << file

      sum
    } 
  end

end
