require 'rubygems'
require 'ffi'

begin
  require 'ffi_yajl/ext'
  module FFI_Yajl
    class Encoder
      include FFI_Yajl::Ext::Encoder
    end
  end
rescue LoadError
  require 'ffi_yajl/ffi'
  module FFI_Yajl
    class Encoder
      include FFI_Yajl::FFI::Encoder
    end
  end
end

module FFI_Yajl
  extend ::FFI::Library

  libname = ::FFI.map_library_name("yajl")
  libpath = File.join(File.dirname(__FILE__), libname)

  if File.file?(libpath)
    # use our vendored version of libyajl2 if we find it installed
    ffi_lib libpath
  else
    ffi_lib 'yajl'
  end

  class YajlCallbacks < ::FFI::Struct
    layout :yajl_null, :pointer,
      :yajl_boolean, :pointer,
      :yajl_integer, :pointer,
      :yajl_double, :pointer,
      :yajl_number, :pointer,
      :yajl_string, :pointer,
      :yajl_start_map, :pointer,
      :yajl_map_key, :pointer,
      :yajl_end_map, :pointer,
      :yajl_start_array, :pointer,
      :yajl_end_array, :pointer
  end

  enum :yajl_status, [
    :yajl_status_ok,
    :yajl_status_client_canceled,
    :yajl_status_insufficient_data,
    :yajl_status_error,
  ]

  enum :yajl_gen_status, [
    :yajl_gen_status_ok,
    :yajl_gen_keys_must_be_strings,
    :yajl_max_depth_exceeded,
    :yajl_gen_in_error_state,
    :yajl_gen_generation_complete,
    :yajl_gen_invalid_number,
    :yajl_gen_no_buf,
  ]

  enum :yajl_option, [
    :yajl_allow_comments, 0x01,
    :yajl_dont_validate_strings, 0x02,
    :yajl_allow_trailing_garbage, 0x04,
    :yajl_allow_multiple_values, 0x08,
    :yajl_allow_partial_values, 0x10,
  ]

  enum :yajl_gen_option, [
    :yajl_gen_beautify, 0x01,
    :yajl_gen_indent_string, 0x02,
    :yajl_gen_print_callback, 0x04,
    :yajl_gen_validate_utf8, 0x08,
  ]

  typedef :pointer, :yajl_handle
  typedef :pointer, :yajl_gen

  # yajl uses unsinged char *'s consistently
  typedef :pointer, :ustring_pointer
  typedef :string, :ustring

  # const char *yajl_status_to_string (yajl_status code)
  attach_function :yajl_status_to_string, [ :yajl_status ], :string
  # yajl_handle yajl_alloc(const yajl_callbacks * callbacks, yajl_alloc_funcs * afs, void * ctx)
  attach_function :yajl_alloc, [:pointer, :pointer, :pointer], :yajl_handle
  # void yajl_free (yajl_handle handle)
  attach_function :yajl_free, [:yajl_handle], :void
  # yajl_status yajl_parse (yajl_handle hand, const unsigned char *jsonText, unsigned int jsonTextLength)
  attach_function :yajl_parse, [:yajl_handle, :ustring, :uint], :yajl_status
  # yajl_status yajl_parse_complete (yajl_handle hand)
  attach_function :yajl_complete_parse, [:yajl_handle], :yajl_status
  # unsigned char *yajl_get_error (yajl_handle hand, int verbose, const unsigned char *jsonText, unsigned int jsonTextLength)
  attach_function :yajl_get_error, [:yajl_handle, :int, :ustring, :int], :ustring
  # void yajl_free_error (yajl_handle hand, unsigned char *str)
  attach_function :yajl_free_error, [:yajl_handle, :ustring], :void

  #
  attach_function :yajl_config, [:yajl_handle, :yajl_option, :int], :int

  attach_function :yajl_gen_config, [:yajl_gen, :yajl_gen_option, :varargs], :int

  # yajl_gen yajl_gen_alloc (const yajl_gen_config *config, const yajl_alloc_funcs *allocFuncs)
  attach_function :yajl_gen_alloc, [:pointer, :pointer], :yajl_gen
  # yajl_gen yajl_gen_alloc2 (const yajl_print_t callback, const yajl_gen_config *config, const yajl_alloc_funcs *allocFuncs, void *ctx)
  # attach_function :yajl_gen_alloc2, [:pointer, :pointer, :pointer, :pointer], :yajl_gen
  # void  yajl_gen_free (yajl_gen handle)
  attach_function :yajl_gen_free, [:yajl_gen], :void

  attach_function :yajl_gen_integer, [:yajl_gen, :long_long], :yajl_gen_status
  attach_function :yajl_gen_double, [:yajl_gen, :double], :yajl_gen_status
  attach_function :yajl_gen_number, [:yajl_gen, :ustring, :int], :yajl_gen_status
  attach_function :yajl_gen_string, [:yajl_gen, :ustring, :int], :int  # XXX: FFI Enums are slow?
  attach_function :yajl_gen_null, [:yajl_gen], :yajl_gen_status
  attach_function :yajl_gen_bool, [:yajl_gen, :int], :yajl_gen_status
  attach_function :yajl_gen_map_open, [:yajl_gen], :yajl_gen_status
  attach_function :yajl_gen_map_close, [:yajl_gen], :yajl_gen_status
  attach_function :yajl_gen_array_open, [:yajl_gen], :yajl_gen_status
  attach_function :yajl_gen_array_close, [:yajl_gen], :yajl_gen_status
  # yajl_gen_status yajl_gen_get_buf (yajl_gen hand, const unsigned char **buf, unsigned int *len)
  attach_function :yajl_gen_get_buf, [:yajl_gen, :pointer ,:pointer], :yajl_gen_status
  # void yajl_gen_clear (yajl_gen hand)
  attach_function :yajl_gen_clear, [:yajl_gen], :void

  class ParseError < StandardError; end
  class EncodeError < StandardError; end

  class Parser
    class State
      attr_accessor :stack, :key_stack, :key

      def initialize
        @stack = Array.new
        @key_stack = Array.new
      end

      def save_key
        key_stack.push(key)
      end

      def restore_key
        @key = key_stack.pop()
      end

      def set_value(val)
        case stack.last
        when Hash
          raise if key.nil?
          stack.last[key] = val
        when Array
          stack.last.push(val)
        else
          raise
        end
      end
    end

    NullCallback = ::FFI::Function.new(:int, [:pointer]) do |ctx|
      @@CTX_MAPPING[ctx.get_ulong(0)].set_value(nil)
      1
    end
    BooleanCallback = ::FFI::Function.new(:int, [:pointer, :int]) do |ctx, boolval|
      @@CTX_MAPPING[ctx.get_ulong(0)].set_value(boolval == 1 ? true : false)
      1
    end
    IntegerCallback = ::FFI::Function.new(:int, [:pointer, :long_long]) do |ctx, intval|
      @@CTX_MAPPING[ctx.get_ulong(0)].set_value(intval)
      1
    end
    DoubleCallback = ::FFI::Function.new(:int, [:pointer, :double]) do |ctx, doubleval|
      @@CTX_MAPPING[ctx.get_ulong(0)].set_value(doubleval)
      1
    end
    NumberCallback = ::FFI::Function.new(:int, [:pointer, :pointer, :size_t]) do |ctx, numberval, numberlen|
      raise "NumberCallback: not implemented"
      1
    end
    StringCallback = ::FFI::Function.new(:int, [:pointer, :string, :size_t]) do |ctx, stringval, stringlen|
      @@CTX_MAPPING[ctx.get_ulong(0)].set_value(stringval.slice(0,stringlen))
      1
    end
    StartMapCallback = ::FFI::Function.new(:int, [:pointer]) do |ctx|
      state = @@CTX_MAPPING[ctx.get_ulong(0)]
      state.save_key
      state.stack.push(Hash.new)
      1
    end
    MapKeyCallback = ::FFI::Function.new(:int, [:pointer, :string, :size_t]) do |ctx, key, keylen|
      @@CTX_MAPPING[ctx.get_ulong(0)].key = key.slice(0,keylen)
      1
    end
    EndMapCallback = ::FFI::Function.new(:int, [:pointer]) do |ctx|
      state = @@CTX_MAPPING[ctx.get_ulong(0)]
      state.restore_key
      state.set_value( state.stack.pop ) if state.stack.length > 1
      1
    end
    StartArrayCallback = ::FFI::Function.new(:int, [:pointer]) do |ctx|
      state = @@CTX_MAPPING[ctx.get_ulong(0)]
      state.save_key
      state.stack.push(Array.new)
      1
    end
    EndArrayCallback = ::FFI::Function.new(:int, [:pointer]) do |ctx|
      state = @@CTX_MAPPING[ctx.get_ulong(0)]
      state.restore_key
      @@CTX_MAPPING[ctx.get_ulong(0)].set_value( @@CTX_MAPPING[ctx.get_ulong(0)].stack.pop ) if @@CTX_MAPPING[ctx.get_ulong(0)].stack.length > 1
      1
    end

    def self.parse(str, opts = {})
      @@CTX_MAPPING ||= Hash.new
      rb_ctx = FFI_Yajl::Parser::State.new()
      @@CTX_MAPPING[rb_ctx.object_id] = rb_ctx
      ctx = ::FFI::MemoryPointer.new(:long)
      ctx.write_long( rb_ctx.object_id )
      callback_ptr = ::FFI::MemoryPointer.new(FFI_Yajl::YajlCallbacks)
      callbacks = FFI_Yajl::YajlCallbacks.new(callback_ptr)
      callbacks[:yajl_null] = NullCallback
      callbacks[:yajl_boolean] = BooleanCallback
      callbacks[:yajl_integer] = IntegerCallback
      callbacks[:yajl_double] = DoubleCallback
      callbacks[:yajl_number] = nil #NumberCallback
      callbacks[:yajl_string] = StringCallback
      callbacks[:yajl_start_map] = StartMapCallback
      callbacks[:yajl_map_key] = MapKeyCallback
      callbacks[:yajl_end_map] = EndMapCallback
      callbacks[:yajl_start_array] = StartArrayCallback
      callbacks[:yajl_end_array] = EndArrayCallback
      yajl_handle = FFI_Yajl.yajl_alloc(callback_ptr, nil, ctx)
      if ( stat = FFI_Yajl.yajl_parse(yajl_handle, str, str.length) != :yajl_status_ok )
        # FIXME: dup the error and call yajl_free_error?
        error = FFI_Yajl.yajl_get_error(yajl_handle, 1, str, str.length)
        raise FFI_Yajl::ParseError.new(error)
      end
      if ( stat = FFI_Yajl.yajl_complete_parse(yajl_handle) != :yajl_status_ok )
        # FIXME: dup the error and call yajl_free_error?
        error = FFI_Yajl.yajl_get_error(yajl_handle, 1, str, str.length)
        raise FFI_Yajl::ParseError.new(error)
      end
      rb_ctx.stack.pop
    ensure
      FFI_Yajl.yajl_free(yajl_handle) if yajl_handle
      @@CTX_MAPPING.delete(rb_ctx.object_id) if rb_ctx && rb_ctx.object_id
    end
  end
end

