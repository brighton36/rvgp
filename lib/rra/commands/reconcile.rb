require 'tempfile'

class RRA::Commands::Reconcile < RRA::CommandBase
  accepts_options OPTION_ALL, OPTION_LIST, [:vsplit, :v]

  VIMSCRIPT_HEADER = <<-EOD
    let $LANG='en_US.utf-8'

    function ReloadIfChanged(timer)
      " There's a bug here where we scroll to the top of the file sometimes, on 
      " reload. Not sure what to do about that...
      checktime
    endfunction

    function ExecuteTransform()
      execute '! /bin/bash -c "\\$(%s transform --concise %%) || read -p \\"(Hit Enter to continue)\\""'
      redraw!
    endfunction
  EOD

  def initialize(*args)
    super *args

    @errors << I18n.t( 'commands.reconcile.errors.unsupported_editor', 
      editor: ENV['EDITOR'].inspect ) unless /vi[m]?\Z/.match ENV['EDITOR']
  end

  def execute!
    Tempfile.create 'reconcile.vim' do |file|
      file.write (VIMSCRIPT_HEADER % [$0])+targets.collect{ |target| 
        target.to_vimscript options[:vsplit] 
      }.join("\ntabnew\n")
      file.close

      system 'vim -S %s' % file.path
    end
  end
  
  class Target < RRA::CommandBase::TransformerTarget
    VIMSCRIPT_TEMPLATE = <<-EOD
    edit %s " output file

    setl autoread

    " NOTE : This was useful for debugging.... Probably this should be nixed...
    " autocmd FileChangedShellPost * echohl WarningMsg | echo "Buffer changed!" | echohl None

    autocmd VimEnter * let timer=timer_start(1000,'ReloadIfChanged', {'repeat': -1} )
    call feedkeys("lh")

    setl nomodifiable

    %s " NOTE: split or vsplit is expected here

    edit %s " input file

    autocmd BufWritePost * silent call ExecuteTransform()

    " NOTE : This was useful for debugging.... Probably this should be nixed...
    "autocmd BufWritePost * echo "on save"
    EOD

    def to_vimscript(is_vsplit)
      # NOTE: I guess we don't need to escape these paths, so long as there arent
      #       any \n's in the path name... I guess
      VIMSCRIPT_TEMPLATE % [ @transformer.output_file, 
        (is_vsplit) ? 'vsplit' : 'split', @transformer.file ]
    end

  end
end
