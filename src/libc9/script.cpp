#include "c9/channel9.hpp"
#include "c9/script.hpp"
#include "pegtl.hh"
#include "json/json.h"

namespace Channel9 {
    namespace script {
        using namespace pegtl;

        struct grammar
            : seq< eof > {};

        Json::Value parse_file(const std::string)
        {
            Json::Value code(Json::arrayValue);

            Json::Value document(Json::objectValue);
            document["code"] = code;
            return code;
        }
    }
}
