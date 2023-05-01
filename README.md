# rra : Ruby Rake Accounting
A workflow tool to: transform bank-downloaded csv's into categorized pta journals. Run finance validations on those journals. And generate reports and graphs on the output.

Here's the help output, for now:
```
Usage: rra [OPTION]... [COMMAND] [TARGET]...
  
rra : rra : Ruby Rake Accounting is a workflow tool for transforming, validating, and reporting your finances in PTA (plain text accounting) and ruby. See the program github for more details.

COMMAND - This is a required parameter. Command-specific options are  further available, once you've specified a command mode:

  cashflow
  Output a convenient dashboard with income/expense flows, based on intention

    -a, --all    Output a dashboard for every intention in the system
    -l, --list   List all available intention-tag values
    -d, --date   Specify a date to use, when calculatingg the "recent months" to display. Defaults to "today".

  grid
  Generate Grid csv's in build/grids

    -a, --all    Process all available grids
    -l, --list   List all available grids

  plot
  Build one or more gnuplots, based on a grid variant.

    -a, --all    Build all available plots
    -l, --list   List all available plots
    -s, --stdout Output build to STDOUT instead of output_file

  publish_gsheets
  Publish plots, both as a spreadsheet, as well as a graph, into a google sheets workbook.

    -a, --all    Publish all available plots
    -l, --list   List all available plot variants
    -c, --csvdir Output the provided plots, as csvs, with grid hacks applied, into the specified directory. Mostly useful for debugging.
    -t, --title  The title of the Google doc being published. Defaults to "RRA Finance Report %m/%d/%y %H:%M". 
    -s, --sleep  Seconds to sleep, between each sheet upload. This sleep prevents Google from aborting the publish, under the auspice of api spamming. Defaults to 5.

  reconcile
  Open an interactive vim session, to edit and build a transform

    -a, --all    Process all available transforms
    -l, --list   List all available transforms
    -v, --vsplit Split the input and output panes vertically, instead of horizontally (the default)

  transform
  Create/Update the build/*.journal, based on ./transformers/*.yml

    -a, --all    Process all available transforms
    -l, --list   List all available transforms
    -s, --stdout Output build to STDOUT instead of output_file
    -c, --concise Concise output mode. Strips output that's unrelated to errors and warnings. (Mostly used by the reconcile command)

  validate_journal
  Validate transformed journals, using the app/validations

    -a, --all    Process all available journals
    -l, --list   List all available journals

  validate_system
  Run validations on the ledger, once the individual journals are valid

    -a, --all    Process all available system validations
    -l, --list   List all available system validations

The following global options are available, to all commands:
  -d --dir[=PATH]  Use the supplied PATH as the active rra directory. 
                   If unsupplied, this option defaults to the basedir of 
                   the LEDGER_FILE environment variable.

```
