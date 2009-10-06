require "compiler-ng"

class CompilerScript
  def initialize
    @files = []
    @transforms = []
    @method_names = []
  end

  def options(argv=ARGV)
    @options = Rubinius::Options.new "Usage: rbx compile-ng [options] [files]", 28

    @options.doc " How to specify the output file"

    @options.on "-o", "--output", "NAME", "Compile single input file to NAME" do |n|
      @output_name = n
    end

    @options.on("-s", "--replace", "FORM",
               "Transform filename, where FORM is pattern:replacement") do |s|
      pattern, @replacement = s.split(":")
      @pattern = Regexp.new pattern
    end


    @options.doc "\n How to transform the AST"
    @options.doc "\n  The default category of transforms are enabled unless specific"
    @options.doc "  ones are selected or --no-transform is given"
    @options.doc ""

    @options.on "-t", "--transform", "NAME", "Enable AST transform NAME" do |t|
      transform = Rubinius::AST::Transforms[t.to_sym]
      @transforms << transform if transform
    end

    @options.on("-T", "--transforms", "NAME",
                "Enable NAME category of AST transforms") do |c|
      if c == "all"
        Rubinius::AST::Transforms.category_map.each do |c, ts|
          @transforms.concat ts
        end
      else
        transforms = Rubinius::AST::Transforms.category c.to_sym
        @transforms.concat transforms if transforms
      end
    end

    @options.on "--no-transform", "Do not transform the AST" do
      @no_transforms = true
    end

    @options.doc "\n     where the transforms are:"
    @options.doc "       Category: all"
    @options.doc "         Includes all transforms\n"

    Rubinius::AST::Transforms.category_map.each do |category, transforms|
      @options.doc "       Category: #{category}"
      transforms.each do |t|
        text = "         %-14s  %s" % [t.transform_name, t.transform_comment]
        @options.doc text
      end
      @options.doc ""
    end


    @options.doc " How to print representations of data structures"

    @options.on "-A", "--print-ast", "Print an ascii graph of the AST" do
      @print_ast = true
    end

    @options.on "-B", "--print-bytecode", "Print bytecode for compiled methods" do
      @print_bytecode = true
    end

    @options.on "-D", "--print-assembly", "Print machine code for compiled methods" do
      @print_assembly = true
    end

    @options.on "-N", "--method", "NAME", "Only decode methods named NAME" do |n|
      @method_names << n
    end

    @options.on "-P", "--print", "Enable all stage printers" do
    end


    @options.doc "\n How to modify runtime behavior"

    @options.on "-i", "--ignore", "Continue on errors" do
      @ignore = true
    end


    @options.doc "\n Help!"

    @options.on "-V", "--verbose", "Print processing information" do
      @verbose = true
    end

    @options.help
    @options.doc ""

    @sources = @options.parse argv
  end

  def help(message=nil)
    puts message, "\n" if message
    puts @options
  end

  def collect_files
    @sources.each do |entry|
      if File.directory? entry
        spec = "#{entry}/**/*.rb"
      else
        spec = entry
      end

      @files += Dir[spec]
    end
  end

  def protect(name)
    begin
      yield
    rescue Object => e
      puts "Failed compiling #{name}"
      if @ignore
        puts e.awesome_backtrace
      else
        raise e
      end
    end
  end

  def enable_transforms(parser)
    return if @no_transforms
    if @transforms.empty?
      parser.default_transforms
    else
      parser.transforms = @transforms
    end
  end

  def run
    if @files.empty?
      help "No files given"
      return
    end

    if @output_name and @files.size > 1
      help "Cannot give output name for multiple input files."
      return
    end

    @files.each do |file|
      puts file if @verbose

      if @pattern
        output = file.gsub(@pattern, @replacement)
        output << "c"
      else
        output = @output_name
      end

      protect file do
        compiler = Rubinius::CompilerNG.new :file, :compiled_file

        if parser = compiler.parser
          parser.root Rubinius::AST::Script
          parser.input file
          enable_transforms parser
          parser.print if @print_ast
        end

        if @print_bytecode or @print_assembly
          if packager = compiler.packager
            printer = packager.print
            printer.bytecode = @print_bytecode
            printer.assembly = @print_assembly
            printer.method_names = @method_names
          end
        end

        if writer = compiler.writer
          writer.name = output
        end

        compiler.run
      end
    end
  end

  def main
    options
    collect_files
    run
  end
end

CompilerScript.new.main
