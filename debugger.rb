require 'readline'

class Debugger
  def initialize
    @file_lines = Hash.new do |hash, path|
      if File.exists? path
        hash[path] = File.readlines(path)
      else
        hash[path] = ["<missing>"]
      end
    end

    @thread = nil
    @frames = []

    @variables = { :show_ip => false }

    @loaded_hook = proc { |file|
      check_defered_breakpoints
    }

    @added_hook = proc { |mod, name, exec|
      check_defered_breakpoints
    }

    Rubinius::CodeLoader.loaded_hook.add @loaded_hook
    Rubinius.add_method_hook.add @added_hook

    @defered_breakpoints = []

    @user_variables = 0

    @breakpoints = []

    @history_path = File.expand_path("~/.rbx_debug")

    if File.exists?(@history_path)
      File.readlines(@history_path).each do |line|
        Readline::HISTORY << line.strip
      end
      @history_io = File.new(@history_path, "a")
    else
      @history_io = File.new(@history_path, "w")
    end

    @history_io.sync = true
  end

  attr_reader :variables

  def self.global
    @global ||= new
  end

  def self.start
    global.start(1)
  end

  def self.here
    global.start(1)
  end

  def spinup_thread
    return if @thread

    @local_channel = Rubinius::Channel.new

    @thread = Thread.new do
      begin
        listen
      rescue Exception => e
        e.render("Listening")
        break
      end

      while true
        begin
          accept_commands
        rescue Exception => e
          begin
            e.render "Error in debugger"
          rescue Exception => e2
            puts "Error rendering backtrace in debugger!"
          end
        end
      end
    end

    @thread.setup_control!(@local_channel)
  end

  def start(offset=0)
    spinup_thread

    # Feed info to the debugger thread!
    locs = Rubinius::VM.backtrace(offset + 1, true)

    method = Rubinius::CompiledMethod.of_sender

    bp = BreakPoint.new "<start>", method, 0, 0
    channel = Rubinius::Channel.new

    @local_channel.send Rubinius::Tuple[bp, Thread.current, channel, locs]

    # wait for the debugger to release us
    channel.receive

    Thread.current.set_debugger_thread @thread
    self
  end

  def listen
    if @channel
      @channel << true
    end

    # Wait for someone to stop
    bp, thr, chan, locs = @local_channel.receive

    # Uncache all frames since we stopped at a new place
    @frames = []

    @locations = locs
    @breakpoint = bp
    @debuggee_thread = thr
    @channel = chan

    @current_frame = frame(0)

    bp.hit!

    puts
    info "Breakpoint: #{@current_frame.describe}"
    show_code
  end

  class Frame
    def initialize(debugger, number, loc)
      @debugger = debugger
      @number = number
      @location = loc
    end

    attr_reader :number, :location

    def run(code)
      eval(code, binding)
    end

    def binding
      @binding ||= Binding.setup(
                     @location.variables,
                     @location.method,
                     @location.static_scope)
    end

    def method
      @location.method
    end

    def line
      @location.line
    end

    def ip
      @location.ip
    end

    def local_variables
      method.local_names
    end

    def describe
      if method.required_args > 0
        locals = []
        0.upto(method.required_args-1) do |arg|
          locals << method.local_names[arg].to_s
        end

        arg_str = locals.join(", ")
      else
        arg_str = ""
      end

      loc = @location

      if loc.is_block
        if arg_str.empty?
          recv = "{ } in #{loc.describe_receiver}#{loc.name}"
        else
          recv = "{|#{arg_str}| } in #{loc.describe_receiver}#{loc.name}"
        end
      else
        if arg_str.empty?
          recv = loc.describe
        else
          recv = "#{loc.describe}(#{arg_str})"
        end
      end

      str = "#{recv} at #{loc.method.active_path}:#{loc.line} (#{loc.ip})"
      if @debugger.variables[:show_ip]
        str << " (+#{loc.ip})"
      end

      str
    end
  end

  def frame(num)
    @frames[num] ||= Frame.new(self, num, @locations[num])
  end

  def accept_commands
    cmd = Readline.readline "debug> "

    if cmd.empty?
      cmd = @last_command
    else
      @last_command = cmd
    end

    command, args = cmd.strip.split(/\s+/, 2)

    case command
    when "b", "break", "brk"
      set_breakpoint(args)
    when "tb", "tbreak"
      set_breakpoint(args, true)
    when "d", "delete"
      delete_breakpoint(args)
    when "dis", "disassemble"
      disassemble(args)
    when "i", "info"
      show_info(args)
    when "n", "next"
      step_over(args)
    when "p"
      eval_code args
    when "c", "cont", "continue"
      listen
    when "bt", "backtrace"
      backtrace(args)
    when "f", "frame"
      set_frame(args)
    when "set"
      set_variable(args)
    when "show"
      show_variable(args)
    else
      puts "Unrecognized command: #{command}"
      return
    end

    # Save it to the history.
    @history_io.puts cmd
  end

  def show_info(args)
    case args.strip
    when "break", "breakpoints", "bp"
      section "Breakpoints"
      if @breakpoints.empty?
        info "No breakpoints set"
      end

      @breakpoints.each_with_index do |bp, i|
        if bp
          info "%3d: %s" % [i+1, bp.describe]
        end
      end
    when "bytecode", "bc"
      show_bytecode
    else
      error "Unknown info: '#{args}'"
    end
  end

  def disassemble(args)
    if args and args.strip == "all"
      section "Bytecode for #{@current_frame.method.name}"
      puts @current_frame.method.decode
    else
      show_bytecode
    end
  end

  def info(str)
    puts "| #{str}"
  end

  def crit(str)
    puts "[CRITICAL] #{str}"
  end

  def error(str)
    puts "* #{str}"
  end

  def section(str)
    puts "==== #{str} ===="
  end

  def ask(str)
    Readline.readline("| #{str}")
  end

  def eval_code(args)
    obj = @current_frame.run(args)

    idx = @user_variables
    @user_variables += 1

    str = "$d#{idx}"
    Rubinius::Globals[str.to_sym] = obj
    puts "#{str} = #{obj.inspect}\n"
  end

  def backtrace(args)
    verbose = (args =~ /-v/)

    if m = /(\d+)/.match(args)
      count = m[1].to_i
    else
      count = nil
    end

    info "Backtrace:"

    each_frame(@current_frame) do |frame|
      return if count and frame.number >= count

      puts "%4d %s" % [frame.number, frame.describe]

      if verbose
        frame.local_variables.each do |local|
          puts "       #{local} = #{frame.run(local.to_s).inspect}"
        end
      end
    end
  end

  def set_frame(args)
    unless m = /(\d+)/.match(args)
      error "Invalid frame number: #{args}"
      return
    end

    num = m[1].to_i

    if num >= @locations.size
      error "Frame #{num} too big"
      return
    end

    @current_frame = frame(num)

    info @current_frame.describe
    show_code
  end

  def each_frame(start=0)
    start = start.number if start.kind_of?(Frame)

    start.upto(@locations.size-1) do |idx|
      yield frame(idx)
    end
  end

  def set_variable(args)
    var, val = args.split(/\s+/, 2)

    if val
      case val.strip
      when "true", "on", "yes", ""
        val = true
      when "false", "off", "no"
        val = false
      when "nil"
        val = nil
      when /\d+/
        val = val.to_i
      end
    else
      val = true
    end

    info "Set '#{var}' = #{val.inspect}"

    @variables[var.to_sym] = val
  end

  def show_variable(args)
    if !args or args.strip.empty?
      @variables.each do |name, val|
        info "var '#{name}' = #{val.inspect}"
      end

      if @user_variables > 0
        section "User variables"
        (0...@user_variables).each do |i|
          str = "$d#{i}"
          val = Rubinius::Globals[str.to_sym]
          info "var #{str} = #{val.inspect}"
        end
      end
    else
      var = args.strip.to_sym
      if @variables.key?(var)
        info "var '#{var}' = #{@variables[var].inspect}"
      else
        error "No variable set named '#{var}'"
      end
    end
  end

  class BreakPoint
    def initialize(descriptor, method, ip, line)
      @descriptor = descriptor
      @method = method
      @ip = ip
      @line = line
      @for_step = false
      @paired_bp = nil
      @temp = false
    end

    attr_reader :method, :ip, :line, :paired_bp, :descriptor

    def location
      "#{@method.active_path}:#{@line} (+#{ip})"
    end

    def describe
      "#{descriptor} - #{location}"
    end

    def for_step!
      @temp = true
      @for_step = true
    end

    def set_temp!
      @temp = true
    end

    def for_step?
      @for_step
    end

    def paired_with(bp)
      @paired_bp = bp
    end

    def remove!
      @method.clear_breakpoint(@ip)
    end

    def hit!
      return unless @temp

      remove!

      @paired_bp.remove! if @paired_bp
    end

    def delete!
      remove!
    end
  end

  class DeferedBreakPoint
    def initialize(debugger, frame, klass, which, name, line=nil, list=nil)
      @debugger = debugger
      @frame = frame
      @klass_name = klass
      @which = which
      @name = name
      @line = line
      @list = list
    end

    def descriptor
      "#{@klass_name}#{@which}#{@name}"
    end

    def resolve!
      begin
        klass = @frame.run(@klass_name)
      rescue NameError
        return false
      end

      begin
        if @which == "#"
          method = klass.instance_method(@name)
        else
          method = klass.method(@name)
        end
      rescue NameError
        return false
      end

      @debugger.info "Resolved breakpoint for #{@klass_name}#{@which}#{@name}"

      @debugger.set_breakpoint_method descriptor, method, @line

      return true
    end

    def describe
      "#{descriptor} - unknown location (defered)"
    end

    def delete!
      if @list
        @list.delete self
      end
    end
  end

  def ask_defered(klass_name, which, name, line)
    answer = ask "Would you like to defer this breakpoint to later? [y/n] "

    if answer.strip.downcase[0] == ?y
      dbp = DeferedBreakPoint.new(self, @current_frame, klass_name, which, name,
                                  line, @defered_breakpoints)
      @defered_breakpoints << dbp
      @breakpoints << dbp

      info "Defered breakpoint created."
    end
  end

  def delete_breakpoint(args)
    if !args or args.empty?
      error "Please specify which breakpoint by number"
      return
    end

    begin
      i = Integer(args.strip)
    rescue ArgumentError
      error "'#{args}' is not a number"
      return
    end

    bp = @breakpoints[i-1]

    unless bp
      error "Unknown breakpoint '#{i}'"
      return
    end

    bp.delete!

    @breakpoints[i-1] = nil
  end

  def set_breakpoint(args, temp=false)
    m = /([A-Z]\w*(?:::[A-Z]\w*)*)([.#])(\w+)(?:[:](\d+))?/.match(args)
    unless m
      error "Unrecognized position: '#{args}'"
      return
    end

    klass_name = m[1]
    which = m[2]
    name  = m[3]
    line =  m[4] ? m[4].to_i : nil

    begin
      klass = @current_frame.run(klass_name)
    rescue NameError
      error "Unable to find class/module: #{m[1]}"
      ask_defered klass_name, which, name, line
      return
    end

    begin
      if which == "#"
        method = klass.instance_method(name)
      else
        method = klass.method(name)
      end
    rescue NameError
      error "Unable to find method '#{name}' in #{klass}"
      ask_defered klass_name, which, name, line
      return
    end

    bp = set_breakpoint_method args.strip, method, line

    bp.set_temp! if temp

    return bp
  end

  def set_breakpoint_method(descriptor, method, line=nil)
    exec = method.executable

    unless exec.kind_of?(Rubinius::CompiledMethod)
      error "Unsupported method type: #{exec.class}"
      return
    end

    if line
      ip = exec.first_ip_on_line(line)

      if ip == -1
        error "Unknown line '#{line}' in method '#{method.name}'"
        return
      end
    else
      line = exec.first_line
      ip = 0
    end

    bp = BreakPoint.new(descriptor, exec, ip, line)
    exec.set_breakpoint ip, bp

    @breakpoints << bp

    info "Set breakpoint #{@breakpoints.size}: #{bp.location}"

    return bp
  end

  def check_defered_breakpoints
    @defered_breakpoints.delete_if do |bp|
      bp.resolve!
    end
  end

  def next_interesting(exec, ip)
    pop = Rubinius::InstructionSet.opcodes_map[:pop]

    if exec.iseq[ip] == pop
      return ip + 1
    end

    return ip
  end

  def goto_between(exec, start, fin)
    goto = Rubinius::InstructionSet.opcodes_map[:goto]
    git  = Rubinius::InstructionSet.opcodes_map[:goto_if_true]
    gif  = Rubinius::InstructionSet.opcodes_map[:goto_if_false]

    iseq = exec.iseq

    i = start
    while i < fin
      op = iseq[i]
      case op
      when goto
        return next_interesting(exec, iseq[i + 1]) # goto target
      when git, gif
        return [next_interesting(exec, iseq[i + 1]),
                next_interesting(exec, i + 2)] # target and next ip
      else
        op = Rubinius::InstructionSet[op]
        i += (op.arg_count + 1)
      end
    end

    return next_interesting(exec, fin)
  end

  def step_to_parent
    @current_frame
    f = frame(@current_frame.number + 1)
    unless f
      info "Unable to find frame to step to next"
      return
    end

    exec = f.method
    ip = f.ip + 1
    line = exec.line_from_ip(ip)

    bp = BreakPoint.new(exec, ip, line)
    bp.for_step!
    exec.set_breakpoint ip, bp

    listen
  end

  def step_over(args)
    if !args or args.empty?
      step = 1
    else
      step = args.to_i
    end

    if step <= 0
      error "Invalid step count - #{step}"
      return
    end

    f = @current_frame

    ip = -1


    exec = f.method
    possible_line = f.line + step
    fin_ip = exec.first_ip_on_line possible_line

    if fin_ip == -1
      step_to_parent
      return
    end

    ips = goto_between(exec, f.ip, fin_ip)
    if ips.kind_of? Fixnum
      ip = ips
    else
      one, two = ips
      bp1 = BreakPoint.new(exec, one, exec.first_ip_on_line(one))
      bp2 = BreakPoint.new(exec, two, exec.first_ip_on_line(two))

      bp1.paired_with(bp2)
      bp2.paired_with(bp1)

      bp1.for_step!
      bp2.for_step!

      exec.set_breakpoint one, bp1
      exec.set_breakpoint two, bp2

      listen
      return
    end

    if ip == -1
      error "No place to step to"
      return
    end

    line = exec.line_from_ip(ip)

    bp = BreakPoint.new(exec, ip, line)
    bp.for_step!

    exec.set_breakpoint ip, bp

    listen
  end

  def show_code(line=@current_frame.line)
    path = @current_frame.method.active_path

    if str = @file_lines[path][line - 1]
      info "#{line}: #{str}"
    else
      show_bytecode(line)
    end
  end

  def show_bytecode(line=@current_frame.line)
    meth = @current_frame.method
    start = meth.first_ip_on_line(line)
    fin = meth.first_ip_on_line(line+1)

    if fin == -1
      fin = meth.iseq.size
    end

    section "Bytecode between #{start} and #{fin-1}"

    partial = meth.iseq.decode_between(start, fin)

    ip = start

    partial.each do |ins|
      op = ins.shift

      ins.each_index do |i|
        case op.args[i]
        when :literal
          ins[i] = meth.literals[ins[i]].inspect
        when :local
          if meth.local_names
            ins[i] = meth.local_names[ins[i]]
          end
        end
      end

      info " %4d: #{op.opcode} #{ins.join(', ')}" % ip

      ip += (ins.size + 1)
    end
  end
end
