#include "c9/value.hpp"
#include "c9/string.hpp"
#include "c9/tuple.hpp"
#include "c9/message.hpp"
#include "c9/context.hpp"

#include <sstream>
#include <stdint.h>

namespace Channel9
{
	Value Nil = {(uint64_t)NIL << Value::TYPE_SHIFT};
	Value True = {(uint64_t)BTRUE << Value::TYPE_SHIFT};
	Value False = {(uint64_t)BFALSE << Value::TYPE_SHIFT};
	Value Undef = {(uint64_t)UNDEF << Value::TYPE_SHIFT};

	bool complex_compare(const Value &l, const Value &r)
	{
		switch (type(l))
		{
		case STRING:
			return *ptr<String>(l) == *ptr<String>(r);
		case TUPLE:
			return *ptr<Tuple>(l) == *ptr<Tuple>(r);
		default:
			return false; // all others compare memory-wise.
		}
	}

	std::string inner_inspect(const Value &val)
	{
		std::stringstream res;
		switch (type(val))
		{
		case NIL: return "nil";
		case UNDEF: return "undef";
		case BFALSE: return "false";
		case BTRUE: return "true";
		case POSITIVE_NUMBER:
		case NEGATIVE_NUMBER: {
			res << "num:";
			res << val.machine_num;
			break;
		}
		case FLOAT_NUM: {
			res << "float:";
			res << float_num(val);
			break;
		}
		case STRING: {
			res << "str:'";
			if (ptr<String>(val)->length() > 128)
				res << ptr<String>(val)->substr(0, 128) << "...";
			else
				res << *ptr<String>(val);
			res << "'";
			break;
		}
		case TUPLE: {
			res << "tuple[" << ptr<Tuple>(val)->size() << "]:(";
			Tuple::const_iterator it;
			int count = 0;
			for (it = ptr<Tuple>(val)->begin(); it != ptr<Tuple>(val)->end(); ++it)
			{
				if (count < 5)
				{
					res << (count==0?"":", ") << inner_inspect(*it);
				} else {
					res << "...";
					break;
				}
				++count;
			}
			res << ")";
			break;
		}
		case MESSAGE: {
			res << "message:[";
			Message::const_iterator it;
			for (it = ptr<Message>(val)->sysargs(); it != ptr<Message>(val)->sysargs_end(); it++)
				res << inner_inspect(*it) << ",";

			res << "]." << ptr<Message>(val)->name() << "(";

			for (it = ptr<Message>(val)->args(); it != ptr<Message>(val)->args_end(); it++)
				res << inner_inspect(*it) << ",";

			res << ")";
			break;
		}
		case CALLABLE_CONTEXT:
			res << "call_ctx:" << ptr<CallableContext>(val) << ":" << ptr<CallableContext>(val)->inspect();
			break;
		case VARIABLE_FRAME:
			res << "variable_frame:" << ptr<VariableFrame>(val);
			break;
		case RUNNING_CONTEXT:
			res << "running_ctx:" << ptr<RunningContext>(val) << ":" << ptr<RunningContext>(val)->inspect();
			break;
		case RUNNABLE_CONTEXT:
			res << "runnable_ctx:" << ptr<RunnableContext>(val) << ":" << ptr<RunnableContext>(val)->inspect();
			break;
		default:
			assert(!type(val));
			break;
		}
		return res.str();
	}
	std::string inspect(const Value &val)
	{
		return std::string("<") + inner_inspect(val) + ">";
	}
}

