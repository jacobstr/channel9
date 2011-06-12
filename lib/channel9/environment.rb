require 'pp'

module Channel9
  # Exits with a status code of 0 regardless of what's passed to it.
  module CleanExitChannel
    def self.channel_send(val, ret)
      pp(:clean_exit => val)
      exit(0)
    end
  end

  # Exits with the status code passed to it.
  module ExitChannel
    def self.channel_send(val, ret)
      pp(:exit => val.to_i)
      exit(val.to_i)
    end
  end

  # Used as a guard when a sender does not expect to be returned to.
  # Just blows things up.
  module InvalidReturnChannel
    def self.channel_send(val, ret)
      raise "Invalid Return, exiting"
    end
  end

  # Used to output information to stdout. Prints whatever's
  # passed to it.
  module StdoutChannel
    def self.channel_send(val, ret)
      $stdout.puts(val)
      ret.channel_send(val, InvalidReturnChannel)
    end
  end

  class Environment
    attr :context
    attr :debug, true

    def initialize(debug = false)
      @context = nil
      @debug = debug
      @special_channels = {
        :clean_exit => CleanExitChannel,
        :exit => ExitChannel,
        :invalid_return => InvalidReturnChannel,
        :stdout => StdoutChannel
      }
    end

    def set_context(context)
      @context = context
    end

    def special_channel(name)
      @special_channels[name]
    end

    def register_special_channel(name, channel)
      @special_channels[name] = channel
    end

    def run(initial_context, value = nil, ret = CleanExitChannel)
      @context = initial_context
      @context.push(value.to_c9)
      @context.push(ret)
      while (instruction = @context.next)
        current_context = @context
        sp = @context.stack.length
          pp(:instruction => {:ip => @context.pos - 1, :instruction => instruction.debug_info}) if @debug
          pp(:before => @context.debug_info) if @debug
        instruction.run(self)
          pp(:orig_after_jump => current_context.debug_info) if @debug && current_context != @context
          pp(:after => @context.debug_info) if @debug
        puts("--------------") if @debug
        stack_should = (sp - instruction.stack_input + instruction.stack_output)
        if (current_context.stack.length != stack_should)
          raise "Stack error: Expected stack depth to be #{stack_should}, was actually #{current_context.stack.length}"
        end
      end
      if (@debug)
        require 'pp'
        pp(
          :final_state => @context.debug_info
        )
      end
    end
  end
end