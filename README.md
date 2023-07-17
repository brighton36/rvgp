# rra : Ruby Rake Accounting
A workflow tool to: transform bank-downloaded csv's into categorized pta journals. Run finance validations on those journals. And generate reports and graphs on the output.

## The Quick Pitch
If you like ruby, and you want something akin to rails... but for your finances - this is what you're looking for! This tool offers an easy workflow,
for the ruby literate, to: 

1. Build PTA Journals, given a csv, and applying reconciliation rules from a provided yaml file
2. Run validations (provided in ruby) to ensure the journals meet your expectations
3. Generate Pretty Plots! using either gnuplot, or Google sheets. Take a look:

### Cashflow
![Cashflow](resources/README.MD/2022-cashflow.png)

### Wealth Report
![Wealth Report](resources/README.MD/all-wealth-growth.png)

Or, publish to google, and share it with your accountant:

### Cashflow
![Cashflow Google](resources/README.MD/2022-cashflow-google.png)

### Wealth Report
![Wealth Report Google](resources/README.MD/all-wealth-growth-google.png)

Plus, you get a bunch of other nice features. Like...
* A TUI cashflow output, for understanding your monthly cashflow on a dashboard
* Lots of versatility in your Plots. The code is very open ended, and supports a good number of 2d plot formats, and features
* No extraneous gem dependencies. Feel free to include activesupport in your project if you'd like. But, we're not imposing that on our requirements!
* A Reconciliation mode in vim, to split-screen edit your yaml, with a hot-loaded output pane
* Git friendly! Store your finances in an easily audited git repo.
* Automatic transactions, for generating transactions via ruby logic, instead of sourcing from a csv file.
* Additional modules for currency conversion, mortgage interest/principle calculations
* Add your own commands and tasks to the rake process, simply by adding commands them your app/commands folder
* An easy quickstart generator, for setting up your first project (see the new_project command)
* Shortcuts for working with finance, currency, gnuplot, hledger and more 

# Getting Started

* TODO

# Documentation

* TODO


