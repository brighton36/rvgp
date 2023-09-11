# frozen_string_literal: true

require 'tempfile'

module RRA
  module Commands
    # This class contains the handling of the 'reconcile' command. Note that
    # there is no rake integration in this command, as that function is irrelevent
    # to the notion of an 'export'.
    class Reconcile < RRA::CommandBase
      accepts_options OPTION_ALL, OPTION_LIST, %i[vsplit v]

      # There's a bug here where we scroll to the top of the file sometimes, on
      # reload. Not sure what to do about that...
      VIMSCRIPT_HEADER = <<-VIMSCRIPT
        let $LANG='en_US.utf-8'

        function ReloadIfChanged(timer)
          checktime
        endfunction

        function ExecuteTransform()
          let transform_path = expand("%%")
          let output_path = tempname()
          let pager = '/bin/less'
          if len($PAGER) > 0
            pager = $PAGER
          endif

          execute('!%<rra_path>s transform --concise ' .
            \\ shellescape(transform_path, 1) .
            \\ ' 2>' . shellescape(output_path, 1) .
            \\ ' > ' . shellescape(output_path, 1))
          if v:shell_error
            echoerr "The following error(s) occurred during transformation:"
            execute '!' . pager . ' -r ' . shellescape(output_path, 1)
            redraw!
          endif
          silent execute('!rm '. shellescape(output_path,1))
        endfunction
      VIMSCRIPT

      def initialize(*args)
        super(*args)

        unless /vim?\Z/.match ENV.fetch('EDITOR')
          @errors << I18n.t('commands.reconcile.errors.unsupported_editor', editor: ENV['EDITOR'].inspect)
        end
      end

      def execute!
        Tempfile.create 'reconcile.vim' do |file|
          file.write [format(VIMSCRIPT_HEADER, rra_path: $PROGRAM_NAME),
                      targets.map { |target| target.to_vimscript options[:vsplit] }.join("\ntabnew\n")].join

          file.close

          system [ENV.fetch('EDITOR'), '-S', file.path].join(' ')
        end
      end

      # This class represents a transformer. See RRA::CommandBase::TransformerTarget, for
      # most of the logic that this class inherits. Typically, these targets take the form
      # of "#{year}-#{transformer_name}"
      class Target < RRA::CommandBase::TransformerTarget
        VIMSCRIPT_TEMPLATE = <<-VIMSCRIPT
        edit %<output_file>s
        setl autoread
        autocmd VimEnter * let timer=timer_start(1000,'ReloadIfChanged', {'repeat': -1} )
        call feedkeys("lh")
        setl nomodifiable
        %<split>s
        edit %<input_file>s
        autocmd BufWritePost * silent call ExecuteTransform()
        VIMSCRIPT

        def to_vimscript(is_vsplit)
          # NOTE: I guess we don't need to escape these paths, so long as there arent
          #       any \n's in the path name... I guess
          format(VIMSCRIPT_TEMPLATE,
                 output_file: @transformer.output_file,
                 input_file: @transformer.file,
                 split: is_vsplit ? 'vsplit' : 'split')
        end
      end
    end
  end
end
