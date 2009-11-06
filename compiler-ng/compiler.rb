module Rubinius
  class CompilerNG
    attr_accessor :parser, :generator, :encoder, :packager, :writer

    # Temporary
    def self.enable
      Compiler.module_eval do
        class << self
          alias_method :old_compile_file, :compile_file
          alias_method :old_compile_string, :compile_string

          define_method :compile_file, CompilerNG.method(:compile_file_obsolete)
          define_method :compile_string, CompilerNG.method(:compile_string_obsolete)
        end
      end
    end

    def self.compile_file_obsolete(file, flags=nil)
      raise "We're sorry, the compiler you're trying to reach has been disconnected."
    end

    def self.compile_string_obsolete(string, binding, file="(eval)", line=1)
      raise "We're sorry, the compiler you're trying to reach has been disconnected."
    end

    def self.compile(file, line=1, output=nil, transforms=:default)
      compiler = new :file, :compiled_file

      parser = compiler.parser
      parser.root AST::Script
      parser.enable_category transforms
      parser.input file, line

      writer = compiler.writer
      writer.name = output

      compiler.run
    end

    # Match old compiler's signature
    def self.compile_file_old(file, flags=nil)
      compile_file file, 1
    end

    def self.compile_file(file, line=1)
      compiler = new :file, :compiled_method

      parser = compiler.parser
      parser.root AST::Script
      parser.default_transforms
      parser.input file, line

      compiler.run
    end

    def self.compile_string(string, file="(eval)", line=1)
      compiler = new :string, :compiled_method

      parser = compiler.parser
      parser.root AST::Script
      parser.default_transforms
      parser.input string, file, line

      compiler.run
    end

    def self.compile_eval(string, binding, file="(eval)", line=1)
      compiler = new :string, :compiled_method

      parser = compiler.parser
      parser.root AST::EvalExpression
      parser.default_transforms
      parser.input string, file, line

      compiler.generator.context = binding

      compiler.run
    end

    def self.compile_test_bytecode(string, transforms)
      compiler = new :string, :bytecode

      parser = compiler.parser
      parser.root AST::Snippit
      parser.input string
      transforms.each { |x| parser.enable_transform x }

      compiler.generator.processor TestGenerator

      compiler.run
    end

    def initialize(from, to)
      @start = Stages[from].new self, to
    end

    def run
      @start.run
    end
  end
end
