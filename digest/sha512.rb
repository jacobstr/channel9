require 'digest'
require 'ext/digest/sha2/sha2'

class Digest::SHA512 < Digest::Instance

  class Context < FFI::Struct

    def self.size # HACK FFI::Struct can't do arrays
      8 * 8 + # state
      8 * 2 + # bitcount
      128 # buffer
    end

  end

  attach_function 'rbx_Digest_SHA512_Init', :sha512_init, [:pointer], :void
  attach_function 'rbx_Digest_SHA512_Update', :sha512_update,
                  [:pointer, :string, :int], :void
  attach_function 'rbx_Digest_SHA512_Finish', :sha512_finish,
                  [:pointer, :string], :void

  def initialize
    reset
  end

  def block_length
    128
  end

  def digest_length
    64
  end

  def finish
    digest = ' ' * digest_length
    self.class.sha512_finish @context.pointer, digest
    digest
  end
  alias digest! finish

  def reset
    @context.free if @context
    @context = Context.new
    self.class.sha512_init @context.pointer
  end

  def update(string)
    self.class.sha512_update @Context.pointer, string, string.length
    self
  end

  alias << update

end

