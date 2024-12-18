# frozen_string_literal: true

require 'tempfile'

module RVGP
  module Commands
    # @!visibility private
    # This class contains the handling of the 'ireconcile' command. Note that
    # there is no rake integration in this command, as that function is irrelevent
    # to the notion of an 'export'.
    class Ireconcile < RVGP::Base::Command
      accepts_options OPTION_ALL, OPTION_LIST, %i[vsplit v]

      # @!visibility private
      ELISP_HEADER = <<~ELISP_HEADER
        (defun rvgp-reconcile-buffer ()
            (message (shell-command-to-string
                        (concat "%<rvgp_path>s reconcile --concise " (buffer-file-name))))
          )

        (defun rvgp-ireconcile-workspace-new (path_reconciler path_journal isHorizontal)
          (switch-to-buffer (find-file path_journal))
          (read-only-mode 1)
          (auto-revert-mode)

          (if isHorizontal (split-window-horizontally) (split-window-vertically))

          (switch-to-buffer (find-file path_reconciler))
          (add-hook 'after-save-hook 'rvgp-reconcile-buffer nil t)
          )
      ELISP_HEADER

      # @!visibility private
      ELISP_TARGET = <<~ELISP_TARGET
        (+workspace/new "%<label>s")
        (rvgp-ireconcile-workspace-new "%<input_file>s" "%<output_file>s" %<split>s)
      ELISP_TARGET

      # @!visibility private
      VIMSCRIPT_HEADER = <<~VIMSCRIPT_HEADER
        let $LANG='en_US.utf-8'

          function ReloadIfChanged(timer)
            checktime
          endfunction

          function ExecuteReconcile()
            let reconcile_path = expand("%%")
            let output_path = tempname()
            let pager = '/bin/less'
            if len($PAGER) > 0
              pager = $PAGER
            endif

            execute('!%<rvgp_path>s reconcile --concise ' .
              \\ shellescape(reconcile_path, 1) .
              \\ ' 2>' . shellescape(output_path, 1) .
              \\ ' > ' . shellescape(output_path, 1))
            if v:shell_error
              echoerr "The following error(s) occurred during reconciliation:"
              execute '!' . pager . ' -r ' . shellescape(output_path, 1)
              redraw!
            endif
            silent execute('!rm '. shellescape(output_path,1))
          endfunction
      VIMSCRIPT_HEADER

      # @!visibility private
      # There's a bug here where we scroll to the top of the file sometimes, on
      # reload. Not sure what to do about that...
      VIMSCRIPT_TARGET = <<~VIMSCRIPT
        edit %<output_file>s
        setl autoread
        autocmd VimEnter * let timer=timer_start(1000,'ReloadIfChanged', {'repeat': -1} )
        call feedkeys("lh")
        setl nomodifiable
        %<split>s
        edit %<input_file>s
        autocmd BufWritePost * silent call ExecuteReconcile()
      VIMSCRIPT

      # @!visibility private
      ELISP_COMMON = {
        ext: 'el',
        # NOTE: It seems that the same split effect is labeled vsplit in vim, and horizontal-split in emacs 🤷🏻
        vsplit: 't',
        hsplit: 'nil',
        target: ELISP_TARGET,
        header: ELISP_HEADER
      }.freeze

      # @!visibility private
      SCRIPTS = {
        vim: {
          command: '%<editor>s -S %<script_path>s',
          ext: 'vim',
          separator: "\ntabnew\n",
          vsplit: 'vsplit',
          hsplit: 'split',
          target: VIMSCRIPT_TARGET,
          header: VIMSCRIPT_HEADER
        },
        emacsclient: { command: '%<editor>s --eval "(load \\"%<script_path>s\\")"' }.merge(ELISP_COMMON),
        emacs: {
          command: '%<editor>s --eval "(add-hook \'window-setup-hook (lambda () (load \\"%<script_path>s\\")))"'
        }.merge(ELISP_COMMON)
      }.freeze

      attr_reader :script

      # @!visibility private
      def initialize(*args)
        super(*args)

        @script = SCRIPTS[editor_class]

        @errors << I18n.t('commands.ireconcile.errors.unsupported_editor', editor: ENV.fetch('EDITOR')) unless @script
      end

      # @!visibility private
      def execute!
        Tempfile.create format('ireconcile.%s', script[:ext]) do |file|
          file.write [format(script[:header], rvgp_path: $PROGRAM_NAME),
                      targets.map do |target|
                        target.to_script(script[:target], script[options[:vsplit] ? :vsplit : :hsplit])
                      end.join(script[:separator])].join # NOTE: We understand and expect :separator is nil for emacs

          file.close

          system format(script[:command], editor: ENV.fetch('EDITOR'), script_path: file.path)
        end
      end

      private

      # NOTE: I assume this matches neovim... perhaps other editors. Nonetheless, I think
      # these proximate checks are a good balance.
      def editor_class
        @editor_class ||= case ENV.fetch('EDITOR')
                          when %r{vim?[^/]*\Z} then :vim
                          when %r{emacsclient[^/]*\Z} then :emacsclient
                          when %r{emacs[^/]*\Z} then :emacs
                          end
      end

      # @!visibility private
      # This class represents a reconciler. See RVGP::Base::Command::ReconcilerTarget, for
      # most of the logic that this class inherits. Typically, these targets take the form
      # of "#\\{year}-#\\{reconciler_name}"
      class Target < RVGP::Base::Command::ReconcilerTarget
        # @!visibility private
        def to_script(format, split)
          # NOTE: I guess we don't need to escape these paths, so long as there arent
          #       any \n's in the path name... I guess
          format(format,
                 output_file: @reconciler.output_file,
                 input_file: @reconciler.file,
                 label: @reconciler.label,
                 split: split)
        end
      end
    end
  end
end
