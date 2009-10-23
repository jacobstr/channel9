module Rubinius
  module AST
    class Alias < Node
      attr_accessor :to, :from

      def initialize(line, to, from)
        @line = line
        @to = to
        @from = from
      end

      def bytecode(g)
        pos(g)

        g.push_scope
        @to.bytecode(g)
        @from.bytecode(g)
        g.send :alias_method, 2, true
      end
    end

    class VAlias < Alias
      def bytecode(g)
        pos(g)

        g.push_const :Rubinius
        g.find_const :Globals
        g.push_literal @from
        g.push_literal @to
        # TODO: fix #add_alias arg order to match #alias_method
        g.send :add_alias, 2
      end
    end

    class Undef < Node
      attr_accessor :name

      def initialize(line, sym)
        @line = line
        @name = sym
      end

      def bytecode(g)
        pos(g)

        g.push_scope
        @name.bytecode(g)
        g.send :__undef_method__, 1
      end
    end

    # Is it weird that Block has the :arguments attribute? Yes. Is it weird
    # that MRI parse tree puts arguments and block_arg in Block? Yes. So we
    # make do and pull them out here rather than having something else reach
    # inside of Block.
    class Block < Node
      attr_accessor :array

      def initialize(line, array)
        @line = line
        @array = array
      end

      def strip_arguments
        if @array.first.kind_of? FormalArguments
          node = @array.shift
          if @array.first.kind_of? BlockArgument
            node.block_arg = @array.shift
          end
          return node
        end
      end

      def children
        @array
      end

      def bytecode(g)
        count = @array.size - 1
        @array.each_with_index do |x, i|
          start_ip = g.ip
          x.bytecode(g)
          g.pop unless start_ip == g.ip or i == count
        end
      end
    end

    class ClosedScope < Node
      include CompilerNG::LocalVariables

      attr_accessor :body

      def new_description(g)
        desc = Compiler::MethodDescription.new(g.class, nil)
        desc.generator.file = g.file
        desc
      end

      def children
        [@body]
      end

      # A nested scope is looking up a local variable. If the variable exists
      # in our local variables hash, return a nested reference to it.
      def search_local(name)
        if variable = variables[name]
          variable.nested_reference
        end
      end

      def new_local(name)
        variable = CompilerNG::LocalVariable.new allocate_slot
        variables[name] = variable
      end

      # There is no place above us that may contain a local variable. Set the
      # local in our local variables hash if not set. Set the local variable
      # node attribute to a reference to the local variable.
      def assign_local_reference(var)
        unless variable = variables[var.name]
          variable = new_local var.name
        end

        var.variable = variable.reference
      end

      def nest_scope(scope)
        scope.parent = self
      end

      def module?
        false
      end

      def attach_and_call(g, name, scoped=false)
        desc = new_description(g)
        desc.name = name

        meth = desc.generator
        meth.name = @name ? @name : name
        meth.push_state self

        if scoped
          meth.push_self
          meth.add_scope
        end

        @body.bytecode meth

        meth.ret
        meth.close

        meth.local_count = local_count
        meth.local_names = local_names

        meth.pop_state

        g.dup
        g.push_const :Rubinius
        g.swap
        g.push_literal name
        g.swap
        g.push_generator desc
        g.swap
        g.push_scope
        g.swap
        g.send :attach_method, 4
        g.pop
        g.send name, 0

        return desc
      end
    end

    class Define < ClosedScope
      attr_accessor :name, :arguments

      def initialize(line, name, block)
        @line = line
        @name = name
        @arguments = block.strip_arguments
        block.array << Nil.new(line) if block.array.empty?
        @body = block
      end

      def compile_body(g)
        desc = new_description(g)
        meth = desc.generator
        meth.name = @name
        meth.push_state self
        meth.state.push_super self
        pos(meth)

        @arguments.bytecode(meth) if @arguments
        @body.bytecode(meth)

        meth.required_args = @arguments.required_args
        meth.total_args = @arguments.total_args
        meth.splat_index = @arguments.splat_index

        meth.local_count = local_count
        meth.local_names = local_names

        meth.ret
        meth.close
        meth.pop_state

        return desc
      end

      def children
        [@arguments, @body]
      end

      def bytecode(g)
        pos(g)

        g.push_const :Rubinius
        g.push_literal @name
        g.push_generator compile_body(g)
        g.push_scope
        g.push_variables
        g.send :method_visibility, 0

        g.send :add_defn_method, 4
      end
    end

    class DefineSingleton < Node
      attr_accessor :receiver, :body

      def initialize(line, receiver, name, block)
        @receiver = receiver
        @body = DefineSingletonScope.new line, name, block
      end

      def children
        [@receiver]
      end

      def bytecode(g)
        pos(g)

        @receiver.bytecode(g)
        @body.bytecode(g)
      end
    end

    class DefineSingletonScope < Define
      def initialize(line, name, block)
        super line, name, block
      end

      def bytecode(g)
        pos(g)

        g.send :metaclass, 0
        g.push_literal @name
        g.push_generator compile_body(g)
        g.push_scope
        g.send :attach_method, 3
      end

      def children
        [@arguments, @body]
      end
    end

    class FormalArguments < Node
      attr_accessor :names, :required, :optional, :defaults, :splat
      attr_reader :block_arg

      def initialize(line, args, defaults, splat)
        @line = line

        if defaults
          defaults = DefaultArguments.new line, defaults
          @defaults = defaults
          @optional = defaults.names

          stop = defaults.names.first
          last = args.each_with_index { |a, i| break i if a == stop }
          @required = args[0, last]
        else
          @required = args.dup
          @optional = []
        end

        args << splat if splat.kind_of? Symbol
        @names = args
        @splat = splat
      end

      def block_arg=(node)
        @names << node.name
        @block_arg = node
      end

      def children
        [@defaults, @block_arg]
      end

      def bytecode(g)
        map_arguments g.state.scope

        @defaults.bytecode(g) if @defaults
        @block_arg.bytecode(g) if @block_arg
      end

      def arity
        @required.size
      end

      def required_args
        @required.size
      end

      def total_args
        @required.size + @optional.size
      end

      def splat_index
        if @splat
          index = @names.size
          index -= 1 if @block_arg
          index -= 1 if @splat.kind_of? Symbol
          index
        end
      end

      def map_arguments(scope)
        @required.each { |arg| scope.new_local arg }
        @defaults.map_arguments scope if @defaults
        scope.new_local @splat if @splat.kind_of? Symbol
        scope.assign_local_reference @block_arg if @block_arg
      end

      def to_actual(line)
        arguments = ActualArguments.new line

        last = -1
        last -= 1 if @block_arg and @block_arg.name == names[last]
        last -= 1 if @splat == names[last]

        arguments.array = @names[0..last].map { |name| LocalVariableAccess.new line, name }

        if @splat.kind_of? Symbol
          arguments.splat = SplatValue.new(line, LocalVariableAccess.new(line, @splat))
        end

        arguments
      end
    end

    class DefaultArguments < Node
      attr_accessor :arguments, :names

      def initialize(line, block)
        @line = line
        array = block.array
        @names = array.map { |a| a.name }
        @arguments = array
      end

      def children
        @arguments
      end

      def map_arguments(scope)
        @arguments.each { |var| scope.assign_local_reference var }
      end

      def bytecode(g)
        @arguments.each do |arg|
          done = g.new_label

          g.passed_arg arg.variable.slot
          g.git done
          arg.bytecode(g)
          g.pop

          done.set!
        end
      end
    end

    module LocalVariable
      attr_accessor :variable
    end

    class BlockArgument < Node
      include LocalVariable

      attr_accessor :name

      def initialize(line, name)
        @line = line
        @name = name
      end

      def bytecode(g)
        pos(g)

        g.push_block
        g.dup
        g.is_nil

        after = g.new_label
        g.git after

        g.push_const :Proc
        g.swap
        g.send :__from_block__, 1

        after.set!

        g.set_local @variable.slot
        g.pop
      end
    end

    class Class < Node
      attr_accessor :name, :superclass, :body

      def initialize(line, name, superclass, body)
        @line = line

        @superclass = superclass ? superclass : Nil.new(line)

        if name.kind_of? Symbol
          @name = ClassName.new line, name, @superclass
        else
          @name = ScopedClassName.new line, name, @superclass
        end

        if body
          @body = ClassScope.new line, @name, body
        else
          @body = EmptyBody.new line
        end
      end

      def children
        [@name, @superclass, @body]
      end

      def bytecode(g)
        @name.bytecode(g)
        @body.bytecode(g)
      end
    end

    class ClassScope < ClosedScope
      def initialize(line, name, body)
        @line = line
        @name = name.name
        @body = body
      end

      def module?
        true
      end

      def children
        [@body]
      end

      def bytecode(g)
        pos(g)

        attach_and_call g, :__class_init__, true
      end
    end

    class ClassName < Node
      attr_accessor :name, :superclass

      def initialize(line, name, superclass)
        @line = line
        @name = name
        @superclass = superclass
      end

      def name_bytecode(g)
        g.push_const :Rubinius
        g.push_literal @name
        @superclass.bytecode(g)
      end

      def bytecode(g)
        pos(g)

        name_bytecode(g)
        g.push_scope
        g.send :open_class, 3
      end

      def children
        [@superclass]
      end
    end

    class ScopedClassName < ClassName
      attr_accessor :parent

      def initialize(line, parent, superclass)
        @line = line
        @name = parent.name
        @parent = parent.parent
        @superclass = superclass
      end

      def bytecode(g)
        pos(g)

        name_bytecode(g)
        @parent.bytecode(g)
        g.send :open_class_under, 3
      end

      def children
        [@superclass, @parent]
      end
    end

    class Module < Node
      attr_accessor :name, :body

      def initialize(line, name, body)
        @line = line

        if name.kind_of? Symbol
          @name = ModuleName.new line, name
        else
          @name = ScopedModuleName.new line, name
        end

        if body
          @body = ModuleScope.new line, @name, body
        else
          @body = EmptyBody.new line
        end
      end

      def children
        [@name, @body]
      end

      def bytecode(g)
        @name.bytecode(g)
        @body.bytecode(g)
      end
    end

    class EmptyBody < Node
      def bytecode(g)
        g.pop
        g.push :nil
      end
    end

    class ModuleName < Node
      attr_accessor :name

      def initialize(line, name)
        @line = line
        @name = name
      end

      def name_bytecode(g)
        g.push_const :Rubinius
        g.push_literal @name
      end

      def bytecode(g)
        pos(g)

        name_bytecode(g)
        g.push_scope
        g.send :open_module, 2
      end
    end

    class ScopedModuleName < ModuleName
      attr_accessor :parent

      def initialize(line, parent)
        @line = line
        @name = parent.name
        @parent = parent.parent
      end

      def bytecode(g)
        pos(g)

        name_bytecode(g)
        @parent.bytecode(g)
        g.send :open_module_under, 2
      end

      def children
        [@parent]
      end
    end

    class ModuleScope < ClosedScope
      def initialize(line, name, body)
        @line = line
        @name = name.name
        @body = body
      end

      def module?
        true
      end

      def children
        [@body]
      end

      def bytecode(g)
        pos(g)

        attach_and_call g, :__module_init__, true
      end
    end

    class SClass < Node
      attr_accessor :receiver

      def initialize(line, receiver, body)
        @line = line
        @receiver = receiver
        @body = SClassScope.new line, body
      end

      def children
        [@receiver, @body]
      end

      def bytecode(g)
        pos(g)
        @receiver.bytecode(g)
        @body.bytecode(g)
      end
    end

    class SClassScope < ClosedScope
      def initialize(line, body)
        @line = line
        @body = body
      end

      def children
        [@body]
      end

      def bytecode(g)
        pos(g)

        g.dup
        g.send :__verify_metaclass__, 0
        g.pop
        g.push_const :Rubinius
        g.swap
        g.send :open_metaclass, 1

        if @body
          attach_and_call g, :__metaclass_init__, true
        else
          g.pop
          g.push :nil
        end
      end
    end

    class Container < ClosedScope
      attr_accessor :file, :name

      def initialize(body)
        @body = body || Nil.new(1)
      end

      def container_bytecode(g)
        g.name = @name
        g.file = @file.to_sym

        yield if block_given?

        g.local_count = local_count
        g.local_names = local_names
      end
    end

    class EvalExpression < Container
      attr_accessor :context

      def initialize(body)
        super body
        @name = :__eval_script__
      end

      def search_scopes(name)
        depth = 1
        scope = @context.variables
        while scope
          if slot = scope.method.local_slot(name)
            return CompilerNG::NestedLocalVariable.new(depth, slot)
          elsif scope.dynamic_locals.key? name
            return CompilerNG::EvalLocalVariable.new(name)
          end

          depth += 1
          scope = scope.parent
        end
      end

      # Returns a cached reference to a variable or searches all
      # surrounding scopes for a variable. If no variable is found,
      # it returns nil and a nested scope will create the variable
      # in itself.
      def search_local(name)
        if variable = variables[name]
          return variable.nested_reference
        end

        if variable = search_scopes(name)
          variables[name] = variable
          return variable.nested_reference
        end
      end

      def new_local(name)
        variable = CompilerNG::EvalLocalVariable.new name
        @context.variables.dynamic_locals[name] = nil
        variables[name] = variable
      end

      def assign_local_reference(var)
        unless reference = search_local(var.name)
          variable = new_local var.name
          reference = variable.reference
        end

        var.variable = reference
      end

      def map_eval
        depth = 0

        visit do |result, node|
          case node
          when ClosedScope
            result = nil
          when Iter
            depth += 1
          when Send
            if node.receiver.kind_of? Self
              if reference = search_local(node.name)
                if reference.kind_of? CompilerNG::NestedLocalReference
                  reference.depth += depth
                end
                node.variable = reference
              end
            end
          end

          result
        end
      end

      def bytecode(g)
        map_eval
        super(g)

        container_bytecode(g) do
          g.push_state self
          @body.bytecode(g)
          g.ret
          g.pop_state
        end
      end
    end

    class Snippit < Container
      def initialize(body)
        super body
        @name = :__snippit__
      end

      def bytecode(g)
        super(g)

        container_bytecode(g) do
          g.push_state self
          @body.bytecode(g)
          g.pop_state
        end
      end
    end

    class Script < Container
      def initialize(body)
        super body
        @name = :__script__
      end

      def bytecode(g)
        super(g)

        container_bytecode(g) do
          g.push_state self
          @body.bytecode(g)
          g.pop
          g.push :true
          g.ret
          g.pop_state
        end
      end
    end

    class Defined < Node
      attr_accessor :expression

      def initialize(line, expr)
        @line = line
        @expression = expr
      end

      def bytecode(g)
        pos(g)

        @expression.defined(g)
      end
    end
  end
end
