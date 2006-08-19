module Rubinius
  module CompiledMethod
    Fields = [:bytecodes, :primitive, :locals, :literals,
      :required, :arguments, :exceptions, :lines]
    
    def self.from_string(bc, lcls)
      obj = allocate()
      obj.bytecodes = ByteArray.from_string(bc)
      obj.primitive = RObject.wrap(-1)
      obj.locals = RObject.wrap(lcls)
      obj.literals = Rubinius::Tuple.new(0)
      obj.required = RObject.wrap(0)
      obj.arguments = Rubinius::Tuple.new(0)
      obj.exceptions = RObject.nil
      obj.lines = RObject.nil
      return obj
    end
  end
  
  add_type :cmethod, CompiledMethod
end