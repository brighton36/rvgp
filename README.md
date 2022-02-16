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
    -d, --date   translation missing: en.help.commands.cashflow.options.date

  reconcile
  Open an interactive vim session, to edit and build a transform

  report
  Generate Reports csv's in build/reports

    -a, --all    Process all available reports
    -l, --list   List all available reports

  transform
  Create/Update the build/*.journal, based on ./transformers/*.yml

    -a, --all    Process all available transforms
    -l, --list   List all available transforms
    -s, --stdout Output build to STDOUT instead of output_file

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
