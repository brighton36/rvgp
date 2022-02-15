require 'tempfile'

class RRA::Commands::Reconcile < RRA::CommandBase
  VIMSCRIPT_TEMPLATE = <<-EOD
  function ReloadIfChanged(timer)
    " There's a bug here where we scroll to the top of the file sometimes, on 
    " reload. Not sure what to do about that...
    checktime
  endfunction

  " Here's the output pane
  edit %s

  setl autoread
  autocmd FileChangedShellPost * echohl WarningMsg | echo "Buffer changed!" | echohl None
  autocmd VimEnter * let timer=timer_start(1000,'ReloadIfChanged', {'repeat': -1} )
  call feedkeys("lh")

  " TODO: vertical split
  split

  " Here's the transformer pane
  edit %s

  " TODO
  "autocmd BufWritePost * execute '! /var/www/sites/mysite/vendor/bin/ecs check %%'
  "autocmd BufWritePost * echo "on save"

  " TODO: Mark the journal buffer read only
  EOD

  def execute!
    # TODO: Block
    # TODO: if EDITOR == vim
    file = Tempfile.new('reconcile.vim')
    # TODO: We need to go through each target, not just zero.
    # TODO: ALso we need to escape
    file.write VIMSCRIPT_TEMPLATE % [
      @transformers[0].output_file, @transformers[0].file ]
    file.close

    system('vim -S %s' % file.path)
    puts "AFter"

    file.unlink
  end
  
end
