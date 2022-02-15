require 'i18n'
require 'pastel'
require 'tty-screen'

module RRA

  # This class doesn't know if it wants to be a logger or something else... Let's
  # see where it ends up
  class StatusOutputRake
    attr_reader :tty_cols

    def initialize(opts = {})
      @semaphore = Mutex.new
      @pastel = opts[:pastel] || Pastel.new

      @last_header_outputted = nil

      begin
        @tty_cols = TTY::Screen.width
      rescue Errno::ENOENT
        @tty_cols = 0
      end

      # NOTE: This is the smallest width I bothered testing on. I don't think 
      # we really care to support this code path in general. If you're this 
      # narrow, umm, fix that.
      @tty_cols = 40 if @tty_cols < 40

      @complete = I18n.t 'status.indicators.complete'
      @indent = I18n.t 'status.indicators.indent'
      @fill = I18n.t 'status.indicators.fill'
      @attention1 = I18n.t 'status.indicators.attention1'
      @attention2 = I18n.t 'status.indicators.attention2'
      @truncated = I18n.t 'status.indicators.truncated'
    end
    
    def info(cmd, desc, &block)
      icon, header, prefix = *%w(icon header prefix).collect{|attr| 
        I18n.t('status.commands.%s.%s' % [cmd.to_s, attr]) }

      @semaphore.synchronize do
        unless @last_header_outputted == cmd
          puts ["\n", icon, " ", @pastel.bold(header)].join
          @last_header_outputted = cmd
        end
      end

      ret = block.call || Hash.new

      has_warn = (ret.has_key?(:warnings) and ret[:warnings].length > 0)
      has_fail = (ret.has_key?(:errors) and ret[:errors].length > 0)

      status_length = ((has_warn and has_fail) ? 
        I18n.t('status.indicators.complete_and', left: @complete, right: @complete) :
          @complete).length

      status = if has_warn and has_fail
         I18n.t 'status.indicators.complete_and', 
           left: @pastel.yellow(@complete), right: @pastel.red(@complete)
       elsif has_warn
         @pastel.yellow(@complete)
       elsif has_fail
         @pastel.red(@complete)
       else
         @pastel.green(@complete)
       end

      fixed_element_width = (
        [@indent, prefix, ' ', @indent, ' ', ' '].join.length + status_length )

      available_width = tty_cols-fixed_element_width

      # If the description is gigantic, we need to constrain it. That's our
      # variable-length column, so to speak:
      fill = if available_width <= desc.length
        # The plus one is due to the compact'd nil below, which, removes a space
        # character, that would have otherwise been placed next to the @fill
        desc = desc[0...available_width-@truncated.length-1]+@truncated
        ' '
       elsif (available_width-desc.length) > 1
        [' ', @fill*(available_width-desc.length-2), ' '].join
       elsif (available_width-desc.length) == 1
        ' '
       else # This should only be zero
        ''
      end

      @semaphore.synchronize do
        puts [ 
          [@indent, @pastel.bold(prefix), ' ', @pastel.blue(desc), fill, status].join,
          (has_warn) ? status_tree(:yellow, ret[:warnings]) : nil, 
          (has_fail) ? status_tree(:red, ret[:errors]) : nil
        ].compact.flatten.join("\n")
      end

      ret
    end

    private

    def status_tree(color, results)
      results.collect{|result| 
        result.each_with_index.collect{|messages, depth|
          ((messages.is_a? String) ? [messages] : messages).collect{|msg|
            [ @indent*2, @indent*depth, 
              (depth > 0) ? @pastel.send(color, @attention2) : 
                @pastel.send(color, @attention1),
                (depth > 0) ? msg : @pastel.send(color, msg) ].join
          }
        }
      }
    end
  end
end
