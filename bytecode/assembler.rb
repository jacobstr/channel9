require 'bytecode/encoder'
require 'object'
require 'cpu/runtime'

module Bytecode
  class Assembler
    
    class Error < RuntimeError
    end
    
    class ExceptionLayoutError < Error
    end
    
    class UnknownException < Error
    end
    
    class Label
      def initialize(name)
        @name = name
        @location = nil
      end
      
      attr_accessor :location
    end
    
    def initialize
      reset
    end
    
    def reset
      @labels = Hash.new { |h,k| h[k] = Label.new(k) }
      @current_op = 0
      @output = []
      @locals = Hash.new
      @literals = []
      @source_lines = []
      @exceptions = Hash.new
      @exception_depth = []
      @primitive = nil
      @arguments = []
    end
    
    attr_reader :labels, :source_lines, :primitive, :literals
    attr_accessor :locals, :exceptions, :arguments
    
    def sorted_exceptions
      initial = @exceptions.values.sort do |a,b|
        if a[0] == b[0]
          a[1] <=> b[1]
        else
          b[1] <=> a[1]
        end
      end
      
      split = []
      idx = 0
      initial.each do |ent|
        nxt = initial[idx + 1]
        if nxt
          # Detect if ent should be split.
          if nxt[0] > ent[0] and nxt[1] < ent[1]
            n1 = [ent[0], nxt[0] - 1, ent.last]
            n2 = [nxt[0], ent[1], ent.last]
            split << n1
            split << n2
          else
            split << ent
          end
        else
          split << ent
        end
        idx += 1
      end
      
      # Resort.
      output = split.sort do |a,b|
        if a[0] == b[0]
          a[1] <=> b[1]
        else
          a[1] <=> b[1]
        end
      end
      
      return output
    end
    
    def assemble(str)
      lines = str.split("\n")
      lines.each { |l| parse_line l }
      translate_labels
      if ent = @source_lines.last
        ent[1] = @current_op
      end
      out = @output
      return out
    end

    def exceptions_as_tuple
      excs = sorted_exceptions()
      tuple_of_int_tuples(excs)
    end
    
    def lines_as_tuple
      tuple_of_int_tuples @source_lines
    end
    
    def tuple_of_int_tuples(excs)
      exctup = Rubinius::Tuple.new(excs.size)
      i = 0
      excs.each do |ary|
        tup = Rubinius::Tuple.new(3)
        tup.put 0, RObject.wrap(ary[0])
        tup.put 1, RObject.wrap(ary[1])
        tup.put 2, RObject.wrap(ary[2])
        exctup.put i, tup
        i += 1
      end
      return exctup
    end
    
    def tuple_of_syms(ary)
      tup = Rubinius::Tuple.new(ary.size)
      i = 0
      ary.each do |t|
        sym = Rubinius::String.new(t.to_s).to_sym
        tup.put i, sym
        i += 1
      end
      return tup
    end
    
    def arguments_as_tuple
      tuple_of_syms @arguments
    end
    
    def literals_as_tuple
      tuple_of_syms @literals      
    end
    
    def bytecodes
      enc = Bytecode::InstructionEncoder.new
      str = @output.inject("") { |a,i| a + enc.encode(*i) }      
    end

    def into_method
      cm = Rubinius::CompiledMethod.from_string(bytecodes, @locals.size)
      if @primitive
        cm.primitive = RObject.wrap(@primitive)
      end
      cm.literals = literals_as_tuple()
      cm.arguments = arguments_as_tuple()
      cm.exceptions = exceptions_as_tuple()
      cm.lines = lines_as_tuple()
      return cm
    end
    
    def translate_labels
      @output.map! do |i|
        next i unless Array === i   
        i.map { |j| Label === j ? j.location : j }
      end
    end
    
    def parse_command(kind, args)
      case kind
      when :line
        if ent = @source_lines.last
          ent[1] = @current_op - 1
        else
          @source_lines << [0, @current_op, 0]
        end
        @source_lines << [@current_op, nil, args.to_i]
      when :exc_start
        name = args.strip.to_sym
        start = @labels[name]
        start.location = @current_op
        @exceptions[name] = [@current_op, nil, nil]
        @exception_depth << name
      when :exceptions
        ename = args.strip.to_sym
        unless @exception_depth.last == ename
          raise ExceptionLayoutError, "Expected #{@exception_depth.last}, got #{ename}"
        end
        name = (args.strip + "_rescue").to_sym
        cur = @labels[name]
        cur.location = @current_op
        
        if ent = @exceptions[ename]
          if ent[1]
            raise ExceptionLayoutError, "Already defined exceptions for #{ename}"
          else
            ent[1] = @current_op
          end
        else
          raise UnknownException, "Couldn't resolve #{ename}"
        end
        
        fin_name = (args.strip + "_end").to_sym
        fin = @labels[fin_name]
        @output << [:goto, fin]
        @current_op += 5
        
        @exceptions[ename][2] = @current_op
        
      when :exc_end
        ename = args.strip.to_sym
        unless @exception_depth.last == ename
          raise ExceptionLayoutError, "Invalid exception layout"
        end
        
        unless ent = @exceptions[ename]
          raise UnknownException, "Couldn't resolve #{ename}"
        end
        
        name = (args.strip + "_end").to_sym
        fin = @labels[name]
        if fin.location
          raise ExceptionLayoutError, "Already defined end of #{ename}"
        end
        fin.location = @current_op
        @exception_depth.pop
      when :primitive
        @primitive = args.to_i
      when :arg
        @arguments << args.strip.to_sym
      else
        raise "Unknown command '#{kind}'"
      end
    end
    
    def parse_line(line)
      if m = /^\s*([^\s]*):(.*)/.match(line)
        name = m[1].to_sym
        @labels[name].location = @current_op
        line = m[2]
      elsif m = /^s*#([^\s]+) (.*)/.match(line)
        kind = m[1].to_sym
        parse_command kind, m[2]
        return
      end
      
      line.strip!
      return if line.empty?
      
      parts = line.split(/\s+/)
      parts[0] = parts[0].to_sym
      parse_operation *parts
    end
    
    Translations = {
      :git => :goto_if_true,
      :gif => :goto_if_false,
      :gid => :goto_if_defined,
      :swap => :swap_stack,
      :dup => :dup_top
    }
    
    Simple = [:noop, :pop, :swap_stack, :dup_top]
    
    def find_local(name)
      cnt = @locals[name]
      return cnt if cnt
      
      cnt = @locals.size + 2
      @locals[name] = cnt
      return cnt
    end
    
    def find_literal(val)
      cnt = @literals.index(val)
      return cnt if cnt
      sz = @literals.size
      @literals << val
      return sz
    end
    
    def parse_lvar(what)
      if /^[a-z_][A-Za-z0-9_]*$/.match(what)
        cnt = find_local(what.to_sym)
        return cnt
      end
      return nil
    end
    
    def parse_ivar(what)
      if /(^[a-z_][A-Za-z0-9_]*)\.(.*)/.match(what)
        cnt = find_local($1.to_sym)
        lit = find_literal(("@" +$2).to_sym)
        return [cnt, lit]
      end
      return nil
    end
    
    def parse_aref(what)
      if /(.*)\[(\d+)\]/.match(what)
        parse_push($1)
        return $2.to_i
      end
    end
    
    def parse_push(what)
      if what[0] == ?&
        lbl = @labels[what[1..-1].to_sym]
        raise "Unknown label '#{lbl}'" unless lbl
        @output << [:push_int, lbl]
      elsif what[0] == ?@
        lit = find_literal(what.to_sym)
        @output << [:push_ivar, lit]
      elsif what.to_i.to_s == what
        @output << [:push_int, what.to_i]
      elsif idx = parse_aref(what)
        @output << [:push_int, idx]
        @output << :fetch_field
        @current_op += 1
      else
        case what
        when "true", true
          @output << :push_true
          @current_op += 1
          return
        when "false", false
          @output << :push_false
          @current_op += 1
          return
        when "nil", nil
          @output << :push_nil
          @current_op += 1
          return
        when "self", :self
          @output << :push_self
          @current_op += 1
        else
          if cnt = parse_lvar(what)
            @output << [:push_local, cnt]
            @current_op += 5
          elsif info = parse_ivar(what)
            @output << [:push_local, info.first]
            @output << [:push_ivar, info.last]
            @current_op += 10
          else
            raise "Unknown push argument '#{what}'"
          end
        end
        return
      end
      @current_op += 5
    end
    
    def parse_set(what)
      if cnt = parse_lvar(what)
        @output << [:set_local, cnt]
        @current_op += 5
      elsif info = parse_ivar(what)
        @output << [:push_local, info.first]
        @output << [:set_ivar, info.last]
        @current_op += 10
      elsif what[0] == ?@
        lit = find_literal(what.to_sym)
        @output << [:set_ivar, lit]
        @current_op += 5
      elsif idx = parse_aref(what)
        @output << [:push_int, idx]
        @output << :store_field
        @current_op += 6
      else
        raise "Unknown set argument '#{what}'"
      end
    end
    
    def parse_operation(*parts)
      op = parts.shift
      if lop = Translations[op]
        op = lop
      end
      
      if Simple.include?(op)
        @output << op
        @current_op += 1
        return
      end
      
      case op
      when :goto, :goto_if_true, :goto_if_false
        label = parts.shift.to_sym
        @output << [op, @labels[label]]
        @current_op += 5
        return
      when :push
        parse_push parts.shift
        return
      when :set
        parse_set parts.shift
        return
      end
      
      if Bytecode::InstructionEncoder::OpCodes.include?(op)
        if Bytecode::InstructionEncoder::IntArg.include?(op)
          @output << [op, part.to_i]
        else
          @output << op
        end
      end
      
      raise "Unknown op '#{op}'"
    end
  end
end