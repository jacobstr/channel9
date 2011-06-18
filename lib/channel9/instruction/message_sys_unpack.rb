module Channel9
  module Instruction
    # message_sys_unpack count
    # ---
    # Unpacks the extra system arguments from the message.
    # 
    # Takes the message at the top of the stack
    #  SP -> message
    # Pushes the message, then count items on to the stack (described below):
    #  SP -> message -> first_sys_arg1 ... -> first_sys_argN
    #
    # If there aren't +count+ system args, fills out extras with nil.
    class MESSAGE_SYS_UNPACK < Base
      def initialize(stream, count)
        super(stream, 1, 1 + count)
        @count = count
      end

      def arguments
        [@count]
      end

      def run(env)
        message = env.context.pop

        pos = 0
        @count.times do
          env.context.push(message.system[pos])
          pos += 1
        end
        env.context.push(message)
      end
    end
  end
end