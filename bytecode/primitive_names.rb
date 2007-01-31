module Bytecode
  class Compiler
    Primitives = [
      :noop,
      :add,
      :sub,
      :equal,
      :compare,
      :at,
      :put,
      :fields,
      :allocate,
      :allocate_count,
      :allocate_bytes,
      :create_block,
      :block_given,
      :block_call,
      :string_to_sexp,
      :load_file,
      :io_write,
      :io_read,
      :fixnum_to_s,
      :logical_class,
      :object_id,
      :hash_set,
      :hash_get,
      :hash_object,
      :symbol_index,
      :symbol_lookup,
      :dup_into,
      :fetch_bytes,
      :compare_bytes,
      :create_pipe,
      :gettimeofday,
      :strftime,
      :load_file,
      :activate_as_script,
      :stat_file,
      :io_open,
      :process_exit,
      :io_close,
      :time_seconds,
      :activate_context,
      :context_sender,
      :micro_sleep,
      :fixnum_mul,
      :bignum_to_s,
      :bignum_add,
      :bignum_sub,
      :bignum_mul,
      :bignum_equal,
      :regexp_new,
      :regexp_match,
      :tuple_shifted,
      :gc_start,
      :file_to_sexp,
      :get_byte,
      :zlib_inflate,
      :zlib_deflate,
      :fixnum_modulo,
      :bytearray_size,
      :terminal_raw,
      :terminal_normal,
      :fixnum_div,
      :marshal_object,
      :unmarshal_object,
      :marshal_to_file,
      :unmarshal_from_file,
      :archive_files,
      :archive_get_file,
      :archive_get_object,
      :archive_add_file,
      :archive_add_object,
      :archive_delete_file,
      :fixnum_and,
      :archive_get_object,
      :time_at,
      :float_to_s,
      :float_add,
      :float_sub,
      :float_mul,
      :float_equal,
      :fixnum_size,
      :file_unlink,
      :fixnum_or,
      :fixnum_xor,
      :fixnum_invert,
      :fixnum_neg,
      :fixnum_shift,
      :bignum_to_float,
      :bignum_and,
      :bignum_or,
      :bignum_xor,
      :bignum_neg,
      :bignum_invert,
      :float_nan_p,
      :float_infinite_p,
      :float_div,
      :float_uminus,
      :bignum_div,
      :float_pow,
      :float_to_i,
      :numeric_coerce,
      :hash_delete,
      :bignum_compare,
      :float_compare,
      :fixnum_to_f,
      :string_to_f,
      :float_divmod,
      :fixnum_divmod,
      :float_floor
    ]

    FirstRuntimePrimitive = 1024

    RuntimePrimitives = [
      :set_ivar,
      :get_ivar,
      :set_index,
      :get_index
    ]
    
  end
end
