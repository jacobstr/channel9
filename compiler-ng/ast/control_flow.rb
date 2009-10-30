module Rubinius
  module AST
    class Case < Node
      attr_accessor :whens, :else

      def initialize(line, whens, else_body)
        @line = line
        @whens = whens
        @else = else_body || Nil.new(line)
      end

      def bytecode(g)
        pos(g)

        done = g.new_label

        @whens.each do |w|
          w.bytecode(g, done)
        end

        @else.bytecode(g)

        done.set!
      end
    end

    class ReceiverCase < Case
      attr_accessor :receiver

      def initialize(line, receiver, whens, else_body)
        @line = line
        @receiver = receiver
        @whens = whens
        @else = else_body || Nil.new(line)
      end

      def bytecode(g)
        pos(g)

        done = g.new_label

        @receiver.bytecode(g)

        @whens.each do |w|
          w.receiver_bytecode(g, done)
        end

        g.pop
        @else.bytecode(g)

        done.set!
      end
    end

    class When < Node
      attr_accessor :conditions, :body, :single, :splat

      def initialize(line, conditions, body)
        @line = line
        @body = body || Nil.new(line)

        if conditions.kind_of? ArrayLiteral
          if conditions.body.last.kind_of? When
            last = conditions.body.pop
            if last.conditions.kind_of? ArrayLiteral
              conditions.body.concat last.conditions.body
            elsif last.single
              @splat = SplatWhen.new line, last.single
            else
              @splat = SplatWhen.new line, last.conditions
            end
          end

          if conditions.body.size == 1 and !@splat
            @single = conditions.body.first
          else
            @conditions = conditions
          end
        else
          @conditions = conditions
        end
      end

      def condition_bytecode(g, condition)
        g.dup
        condition.bytecode(g)
        g.swap
        g.send :===, 1
      end

      def receiver_bytecode(g, done)
        body = g.new_label
        nxt = g.new_label

        if @single
          condition_bytecode(g, @single)
          g.gif nxt
        else
          if @conditions
            @conditions.body.each do |c|
              condition_bytecode(g, c)
              g.git body
            end
          end

          @splat.receiver_bytecode(g, body, nxt) if @splat
          g.goto nxt

          body.set!
        end

        g.pop
        @body.bytecode(g)
        g.goto done

        nxt.set!
      end

      def bytecode(g, done)
        pos(g)

        nxt = g.new_label
        body = g.new_label

        if @single
          @single.bytecode(g)
          g.gif nxt
        else
          if @conditions
            @conditions.body.each do |condition|
              condition.bytecode(g)
              g.git body
            end
          end

          @splat.bytecode(g, body, nxt) if @splat
          g.goto nxt

          body.set!
        end

        @body.bytecode(g)
        g.goto done

        nxt.set!
      end
    end

    class SplatWhen < Node
      attr_accessor :condition

      def initialize(line, condition)
        @line = line
        @condition = condition
      end

      def receiver_bytecode(g, body, nxt)
        pos(g)

        g.dup
        @condition.bytecode(g)
        g.cast_array
        g.swap
        g.send :__matches_when__, 1
        g.git body
      end

      def bytecode(g, body, nxt)
      end
    end

    class Flip2 < Node
      def initialize(line, start, finish)
        @line = line
        @start = start
        @finish = finish
      end

      def bytecode(g)
      end
    end

    class Flip3 < Node
      def initialize(line, start, finish)
        @line = line
        @start = start
        @finish = finish
      end

      def bytecode(g)
      end
    end

    class If < Node
      attr_accessor :condition, :body, :else

      def initialize(line, condition, body, else_body)
        @line = line
        @condition = condition
        @body = body || Nil.new(line)
        @else = else_body || Nil.new(line)
      end

      def bytecode(g)
        pos(g)

        done = g.new_label
        else_label = g.new_label

        @condition.bytecode(g)
        g.gif else_label

        @body.bytecode(g)
        g.goto done

        else_label.set!
        @else.bytecode(g)

        done.set!
      end
    end

    class While < Node
      attr_accessor :condition, :body, :check_first

      def initialize(line, condition, body, check_first)
        @line = line
        @condition = condition
        @body = body || Nil.new(line)
        @check_first = check_first
      end

      def bytecode(g, use_gif=true)
        pos(g)

        g.push_modifiers

        top = g.new_label
        bot = g.new_label
        g.break = g.new_label

        if @check_first
          g.redo = g.new_label
          g.next = top

          top.set!

          @condition.bytecode(g)
          if use_gif
            g.gif bot
          else
            g.git bot
          end

          g.redo.set!

          @body.bytecode(g)
          g.pop
        else
          g.next = g.new_label
          g.redo = top

          top.set!

          @body.bytecode(g)
          g.pop

          g.next.set!
          @condition.bytecode(g)
          if use_gif
            g.gif bot
          else
            g.git bot
          end
        end

        g.check_interrupts
        g.goto top

        bot.set!
        g.push :nil
        g.break.set!

        g.pop_modifiers
      end
    end

    class Until < While
      def bytecode(g)
        super(g, false)
      end
    end

    class Match < Node
      attr_accessor :pattern

      def initialize(line, pattern, flags)
        @line = line
        @pattern = RegexLiteral.new line, pattern, flags
      end

      def bytecode(g)
        pos(g)

        g.push_const :Rubinius
        g.find_const :Globals
        g.push_literal :$_
        g.send :[], 1

        @pattern.bytecode(g)

        g.send :=~, 1
      end
    end

    class Match2 < Node
      attr_accessor :pattern, :value

      def initialize(line, pattern, value)
        @line = line
        @pattern = pattern
        @value = value
      end

      def bytecode(g)
        pos(g)

        @pattern.bytecode(g)
        @value.bytecode(g)
        g.send :=~, 1
      end
    end

    class Match3 < Node
      attr_accessor :pattern, :value

      def initialize(line, pattern, value)
        @line = line
        @pattern = pattern
        @value = value
      end

      def bytecode(g)
        pos(g)

        @value.bytecode(g)
        @pattern.bytecode(g)
        g.send :=~, 1
      end
    end

    class Break < Node
      attr_accessor :value

      def initialize(line, expr)
        @line = line
        @value = expr || Nil.new(line)
      end

      def jump_error(g, msg)
        g.push :self
        g.push_const :LocalJumpError
        g.push_literal msg
        g.send :raise, 2, true
      end

      def bytecode(g)
        pos(g)

        @value.bytecode(g)

        if g.break
          g.goto g.break
        elsif g.state.block?
          g.raise_break
        else
          g.pop
          g.push_const :Compiler
          g.find_const :Utils
          g.send :__unexpected_break__, 0
        end
      end
    end

    class Next < Break
      def initialize(line, value)
        @line = line
        @value = value
      end

      def bytecode(g)
        pos(g)

        if g.next
          g.goto g.next
        elsif g.state.block?
          if @value
            @value.bytecode(g)
          else
            g.push :nil
          end
          g.ret
        else
          @value.bytecode(g) if @value # next(raise("foo")) ha ha ha
          jump_error g, "next used in invalid context"
        end
      end
    end

    class Redo < Break
      def initialize(line)
        @line = line
      end

      def bytecode(g)
        pos(g)

        if g.redo
          g.goto g.redo
        else
          jump_error g, "redo used in invalid context"
        end
      end
    end

    class Retry < Break
      def initialize(line)
        @line = line
      end

      def bytecode(g)
        pos(g)

        if g.retry
          g.goto g.retry
        else
          jump_error g, "retry used in invalid context"
        end
      end
    end

    class Return < Node
      attr_accessor :value

      def initialize(line, expr)
        @line = line
        @value = expr
      end

      def bytecode(g, force=false)
        pos(g)

        # Literal ArrayList and a splat
        if @splat
          splat_node = @value.body.pop
          @value.bytecode(g)
          splat_node.call_bytecode(g)
          g.send :+, 1
        elsif @value
          @value.bytecode(g)
        else
          g.push :nil
        end

        if g.state.rescue?
          g.clear_exception
        end

        if g.state.block?
          g.raise_return
        elsif !force and g.state.ensure?
          g.ensure_return
        else
          g.ret
        end
      end
    end
  end
end
