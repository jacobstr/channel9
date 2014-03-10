#pragma once

#include "json/json.h"

namespace Channel9 {
    namespace script {
        Json::Value parse_file(const std::string &filename);
        Json::Value parse_string(const std::string &str);
    }
}
