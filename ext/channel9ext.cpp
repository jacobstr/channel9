extern "C" {
#	include "ruby.h"
#	include "intern.h"
}
#include "environment.hpp"
#include "context.hpp"
#include "value.hpp"
#include "istream.hpp"
#include "message.hpp"

using namespace Channel9;

typedef VALUE (*ruby_method)(ANYARGS);

VALUE rb_mChannel9;
VALUE rb_mPrimitive;

VALUE rb_cEnvironment;
VALUE rb_cStream;
VALUE rb_cContext;
VALUE rb_cCallableContext;
VALUE rb_cRunnableContext;
VALUE rb_cMessage;
VALUE rb_cUndef;
VALUE rb_Undef;

static VALUE c9_to_rb(const Value &val);
static Value rb_to_c9(VALUE val);
static VALUE rb_Environment_new(Environment *env);
static VALUE rb_Message_new(const Message *msg);
static VALUE rb_CallableContext_new(CallableContext *ctx);
static VALUE rb_RunnableContext_new(RunnableContext *ctx);

class RubyChannel : public CallableContext
{
private:
	VALUE m_val;

public:
	RubyChannel(VALUE val) : m_val(val) {}

	void send(Environment *env, const Value &val, const Value &ret)
	{
		DO_DEBUG printf("Oh hi %s\n", STR2CSTR(rb_funcall(rb_class_of(m_val), rb_intern("to_s"), 0)));
		rb_funcall(m_val, rb_intern("channel_send"), 3,
			rb_Environment_new(env), c9_to_rb(val), c9_to_rb(ret));
	}
};

static Value rb_to_c9(VALUE val)
{
	int type = TYPE(val);
	switch (type)
	{
	case T_NIL:
		return Value::Nil;
	case T_FALSE:
		return Value::False;
	case T_TRUE:
		return Value::True;
	case T_SYMBOL:
		return value(rb_id2name(val));
	case T_STRING:
		return value(STR2CSTR(val));
	case T_FIXNUM:
		return value((long long)FIX2INT(val));
	case T_ARRAY: {
		Value::vector tuple;
		size_t len = RARRAY_LEN(val);
		for (size_t i = 0; i < len; ++i)
		{
			tuple.push_back(rb_to_c9(rb_ary_entry(val, i)));
		}
		return value(tuple);
		}
	case T_MODULE:
	case T_CLASS:
	case T_OBJECT:
		if (rb_respond_to(val, rb_intern("channel_send")))
		{
			return value(new RubyChannel(val));
		}
	default:
		rb_raise(rb_eRuntimeError, "Could not convert object %s (%d) to c9 object.", 
			STR2CSTR(rb_funcall(val, rb_intern("to_s"), 0)), type);
	}
	return Value::Nil;
}

static VALUE c9_to_rb(const Value &val)
{
	switch (val.m_type)
	{
	case NIL:
		return Qnil;
	case UNDEF:
		return rb_Undef;
	case BFALSE:
		return Qfalse;
	case BTRUE:
		return Qtrue;
	case MACHINE_NUM:
		return INT2FIX(val.machine_num);
	case FLOAT_NUM:
		return rb_float_new(val.float_num);
	case STRING:
		return rb_intern(val.str->c_str());
	case TUPLE: {
		VALUE ary = rb_ary_new();
		for (Value::vector::const_iterator it = val.tuple->begin(); it != val.tuple->end(); ++it)
		{
			rb_ary_push(ary, c9_to_rb(*it));
		}
		return ary;
		}
	case MESSAGE:
		return rb_Message_new(val.msg);
	case CALLABLE_CONTEXT:
		return rb_CallableContext_new(val.call_ctx);
	case RUNNABLE_CONTEXT:
		return rb_RunnableContext_new(val.ret_ctx);
	default:
		printf("Unknown value type %d\n", val.m_type);
		exit(1);
	}
	return Qnil;
}

static VALUE rb_Environment_new(Environment *env)
{
	VALUE obj = Data_Wrap_Struct(rb_cEnvironment, 0, 0, env);
	VALUE debug = Qfalse;
	rb_obj_call_init(obj, 1, &debug);
	return obj;
}

static VALUE Environment_new(VALUE self, VALUE debug)
{
	Environment *env = new Environment();
	VALUE obj = Data_Wrap_Struct(rb_cEnvironment, 0, 0, env);
	rb_obj_call_init(obj, 1, &debug);
	return obj;
}

static VALUE Environment_special_channel(VALUE self, VALUE name)
{
	Environment *env;
	Data_Get_Struct(self, Environment, env);
	return c9_to_rb(env->special_channel(rb_id2name(SYM2ID(name))));
}
static VALUE Environment_set_special_channel(VALUE self, VALUE name, VALUE channel)
{
	Environment *env;
	Data_Get_Struct(self, Environment, env);
	env->set_special_channel(rb_id2name(SYM2ID(name)), rb_to_c9(channel));
	return Qnil;
}

static void Init_Channel9_Environment()
{
	rb_cEnvironment = rb_define_class_under(rb_mChannel9, "Environment", rb_cObject);
	rb_define_singleton_method(rb_cEnvironment, "new", ruby_method(Environment_new), 1);
	rb_define_method(rb_cEnvironment, "special_channel", ruby_method(Environment_special_channel), 1);
	rb_define_method(rb_cEnvironment, "set_special_channel", ruby_method(Environment_set_special_channel), 2);
}

static VALUE Stream_new(VALUE self)
{
	IStream *stream = new IStream();
	VALUE obj = Data_Wrap_Struct(rb_cStream, 0, 0, stream);
	rb_obj_call_init(obj, 0, 0);
	return obj;
}

static VALUE Stream_add_instruction(VALUE self, VALUE name, VALUE args)
{
	IStream *stream;
	Data_Get_Struct(self, IStream, stream);

	Instruction instruction;
	instruction.instruction = inum(STR2CSTR(name));

	size_t argc = RARRAY_LEN(args);
	if (argc > 0)
		instruction.arg1 = rb_to_c9(rb_ary_entry(args, 0));
	
	if (argc > 1)
		instruction.arg2 = rb_to_c9(rb_ary_entry(args, 1));

	if (argc > 2)
		instruction.arg3 = rb_to_c9(rb_ary_entry(args, 2));

	stream->add(instruction);

	return self;
}

static VALUE Stream_add_label(VALUE self, VALUE name)
{
	IStream *stream;
	Data_Get_Struct(self, IStream, stream);

	stream->set_label(STR2CSTR(name));

	return self;
}

static VALUE Stream_add_line_info(VALUE self, VALUE file, VALUE line, VALUE pos, VALUE extra)
{
	IStream *stream;
	Data_Get_Struct(self, IStream, stream);

	stream->set_source_pos(SourcePos(STR2CSTR(file), FIX2INT(line), FIX2INT(pos), STR2CSTR(extra)));

	return self;
}

static void Init_Channel9_Stream()
{
	rb_cStream = rb_define_class_under(rb_mChannel9, "Stream", rb_cObject);
	rb_define_singleton_method(rb_cStream, "new", ruby_method(Stream_new), 0);
	rb_define_method(rb_cStream, "add_instruction", ruby_method(Stream_add_instruction), 2);
	rb_define_method(rb_cStream, "add_label", ruby_method(Stream_add_label), 1);
	rb_define_method(rb_cStream, "add_line_info", ruby_method(Stream_add_line_info), 4);
}

static VALUE Context_new(VALUE self, VALUE rb_env, VALUE rb_stream)
{
	Environment *env;
	IStream *stream;

	Data_Get_Struct(rb_env, Environment, env);
	Data_Get_Struct(rb_stream, IStream, stream);

	BytecodeContext *ctx = new BytecodeContext(env, stream);
	VALUE obj = Data_Wrap_Struct(rb_cContext, 0, 0, ctx);
	VALUE argv[2] = {rb_env, rb_stream};
	rb_obj_call_init(obj, 2, argv);
	return obj;
}

static VALUE Context_channel_send(VALUE self, VALUE rb_cenv, VALUE rb_val, VALUE rb_ret)
{
	Environment *cenv;
	BytecodeContext *ctx;

	Data_Get_Struct(rb_cenv, Environment, cenv);
	Data_Get_Struct(self, BytecodeContext, ctx);

	ctx->send(cenv, rb_to_c9(rb_val), rb_to_c9(rb_ret));

	return Qnil;
}

static void Init_Channel9_Context()
{
	rb_cContext = rb_define_class_under(rb_mChannel9, "Context", rb_cObject);
	rb_define_singleton_method(rb_cContext, "new", ruby_method(Context_new), 2);
	rb_define_method(rb_cContext, "channel_send", ruby_method(Context_channel_send), 3);
}

static VALUE rb_CallableContext_new(CallableContext *ctx)
{
	VALUE obj = Data_Wrap_Struct(rb_cCallableContext, 0, 0, ctx);
	rb_obj_call_init(obj, 0, 0);
	return obj;
}

static VALUE CallableContext_channel_send(VALUE self, VALUE rb_cenv, VALUE rb_val, VALUE rb_ret)
{
	Environment *cenv;
	CallableContext *ctx;

	Data_Get_Struct(rb_cenv, Environment, cenv);
	Data_Get_Struct(self, CallableContext, ctx);

	ctx->send(cenv, rb_to_c9(rb_val), rb_to_c9(rb_ret));

	return Qnil;
}

static void Init_Channel9_CallableContext()
{
	rb_cCallableContext = rb_define_class_under(rb_mChannel9, "CallableContext", rb_cObject);
	rb_define_method(rb_cCallableContext, "channel_send", ruby_method(CallableContext_channel_send), 3);
}

static VALUE rb_RunnableContext_new(RunnableContext *ctx)
{
	VALUE obj = Data_Wrap_Struct(rb_cRunnableContext, 0, 0, ctx);
	rb_obj_call_init(obj, 0, 0);
	return obj;
}

static VALUE RunnableContext_channel_send(VALUE self, VALUE rb_cenv, VALUE rb_val, VALUE rb_ret)
{
	Environment *cenv;
	RunnableContext *ctx;

	Data_Get_Struct(rb_cenv, Environment, cenv);
	Data_Get_Struct(self, RunnableContext, ctx);

	ctx->send(cenv, rb_to_c9(rb_val), rb_to_c9(rb_ret));

	return Qnil;
}

static void Init_Channel9_RunnableContext()
{
	rb_cRunnableContext = rb_define_class_under(rb_mChannel9, "RunnableContext", rb_cObject);
	rb_define_method(rb_cRunnableContext, "channel_send", ruby_method(RunnableContext_channel_send), 3);
}

static VALUE rb_Message_new(const Message *msg)
{
	VALUE obj = Data_Wrap_Struct(rb_cMessage, 0, 0, (void*)msg);
	VALUE argv[3] = {c9_to_rb(value(msg->name())), c9_to_rb(value(msg->sysargs())), c9_to_rb(value(msg->args()))};
	rb_obj_call_init(obj, 3, argv);	
	return obj;
}

static VALUE Message_new(VALUE self, VALUE name, VALUE sysargs, VALUE args)
{
	Value c9_name = rb_to_c9(name);
	Value c9_sysargs = rb_to_c9(sysargs);
	Value c9_args = rb_to_c9(args);

	Message *msg = new Message(c9_name.str->c_str(), *c9_sysargs.tuple, *c9_args.tuple);
	VALUE obj = Data_Wrap_Struct(rb_cMessage, 0, 0, msg);
	VALUE argv[3] = {name, sysargs, args};
	rb_obj_call_init(obj, 3, argv);
	return obj;
}

static void Init_Channel9_Message()
{
	rb_cMessage = rb_define_class_under(rb_mPrimitive, "Message", rb_cObject);
	rb_define_singleton_method(rb_cMessage, "new", ruby_method(Message_new), 3);
}

static void Init_Channel9_Undef()
{
	rb_cUndef = rb_define_class_under(rb_mPrimitive, "Undef", rb_cObject);
	rb_Undef = rb_class_new_instance(0, 0, rb_cUndef);
}

extern "C" void Init_channel9ext()
{
	rb_mChannel9 = rb_define_module("Channel9");
	rb_mPrimitive = rb_define_module_under(rb_mChannel9, "Primitive");
	Init_Channel9_Environment();
	Init_Channel9_Stream();
	Init_Channel9_Message();
	Init_Channel9_Undef();
	Init_Channel9_Context();
	Init_Channel9_RunnableContext();
	Init_Channel9_CallableContext();
}