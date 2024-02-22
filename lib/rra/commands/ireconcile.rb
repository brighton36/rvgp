# frozen_string_literal: true

require 'tempfile'

module RRA
  module Commands
    # @!visibility private
    # This class contains the handling of the 'ireconcile' command. Note that
    # there is no rake integration in this command, as that function is irrelevent
    # to the notion of an 'export'.
    class Ireconcile < RRA::Base::Command
      accepts_options OPTION_ALL, OPTION_LIST, %i[vsplit v]

      # There's a bug here where we scroll to the top of the file sometimes, on
      # reload. Not sure what to do about that...
      # @!visibility private
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

      # @!visibility private
      def initialize(*args)
        super(*args)

        unless /vim?\Z/.match ENV.fetch('EDITOR')
          @errors << I18n.t('commands.ireconcile.errors.unsupported_editor', editor: ENV['EDITOR'].inspect)
        end
      end

      # @!visibility private
      def execute!
        Tempfile.create 'ireconcile.vim' do |file|
          file.write [format(VIMSCRIPT_HEADER, rra_path: $PROGRAM_NAME),
                      targets.map { |target| target.to_vimscript options[:vsplit] }.join("\ntabnew\n")].join

          file.close

          system [ENV.fetch('EDITOR'), '-S', file.path].join(' ')
        end
      end

      # @!visibility private
      # This class represents a transformer. See RRA::Base::Command::ReconcilerTarget, for
      # most of the logic that this class inherits. Typically, these targets take the form
      # of "#\\{year}-#\\{transformer_name}"
      class Target < RRA::Base::Command::ReconcilerTarget
        # @!visibility private
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

        # @!visibility private
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
