require 'parslet'

module Channel9
  module Script
    class Parser < Parslet::Parser
      rule(:ws) { match('[ \t]').repeat(1) }
      rule(:ws?) { ws.maybe }
      rule(:br) { str("\n") }

      rule(:line_comment_text) { (br.absnt? >> any).repeat }
      rule(:multiline_comment_text) { (str('*/').absnt? >> any).repeat }

      rule(:comment) { 
        str('#') >> line_comment_text.as(:text) |
        str('//') >> line_comment_text.as(:text) |
        str('/*') >> multiline_comment_text.as(:text) >> str('*/')
      }

      # Empty whitespace is any whitespace that has no content of any sort (
      # so unlike iws, it doesn't include comments).
      # Basically, it's whitespace before something really starts.
      rule(:ews) { (ws | br).repeat(1) }
      rule(:ews?) { ews.maybe }

      # Line whitespace is any kind of whitespace on the same line (including comments).
      # Use for stuff that shouldn't go to the next line, but still expects something
      # more to complete the expression (eg. a >> lws >> '+' >> iws >> b)
      rule(:lws) { (ws | comment.as(:inline_doc)).repeat(1) }
      rule(:lws?) { lws.maybe }

      # Inner whitespace is space between elements of the same line.
      # It can include spaces, line breaks, and comments.
      rule(:iws) { (ws | br | comment.as(:inline_doc)).repeat(1) }
      rule(:iws?) { iws.maybe }

      # End of line can be any amount of whitespace, including comments,
      # and ending in either a \n or semicolon
      rule(:eol) { (ws | comment.as(:inline_doc)).repeat >> (br | str(';')) }

      rule(:symbol) {
        match('[a-zA-Z_]') >> match('[a-zA-Z0-9_]').repeat
      }
      rule(:method_name) {
        (symbol >> str(':') >> symbol) |
        symbol
      }

      rule(:local_var) {
        symbol.as(:local_var)
      }
      rule(:var_type) {
        (str("lexical") | str("local") | str("frame"))
      }
      rule(:declare_var) {
        (var_type.as(:type) >> lws >> symbol.as(:declare_var) >> lws? >> str("=") >> lws? >> expression.as(:assign)) |
        (var_type.as(:type) >> lws >> symbol.as(:declare_var))
      }
      rule(:arg_declare_var) {
        (var_type.as(:type) >> lws >> symbol.as(:declare_var)) |
        symbol.as(:declare_var)
      }
      rule(:special_var) {
        str('$') >> symbol.as(:special_var)
      }

      rule(:variable) { # Note: order IS important here.
        (declare_var | local_var | special_var)
      }

      rule(:nil_const) {
        str("nil").as(:nil)
      }
      rule(:undef_const) {
        str("undef").as(:undef)
      }
      rule(:true_const) {
        str("true").as(:true)
      }
      rule(:false_const) {
        str("false").as(:false)
      }

      rule(:integer_const) {
        match('[0-9]').repeat(1).as(:integer)
      }

      rule(:string_const) {
        ((str('"') >> str('"').absent?.maybe.as(:string) >> str('"')) |
         (str("'") >> str("'").absent?.maybe.as(:string) >> str("'")) |
         (str('"') >> (str('"').absnt? >> any).repeat.as(:string) >> str('"')) |
         (str("'") >> (str("'").absnt? >> any).repeat.as(:string) >> str("'")) |
         (str(":") >> symbol.as(:string))
        )
      }

      rule(:message_id_const) {
        str('@').as(:message_id) >> string_const
      }
      rule(:protocol_id_const) {
        str('@@').as(:protocol_id) >> string_const
      }

      rule(:list_const) {
        (str("[") >> iws? >> (expression >> iws? >> str(",").maybe).repeat >> iws? >> str("]")).as(:list)
      }

      rule(:argdef) {
        arg_declare_var >> (iws? >> str(',') >> iws? >> arg_declare_var).repeat
      }

      rule(:argdef_list) {
        (str('(') >> iws? >> argdef.as(:args) >> iws? >> str(",") >> iws? >> str('@') >> arg_declare_var.as(:msg_var) >> iws? >> str(')')) |
        (str('(') >> iws? >> str('@') >> arg_declare_var.as(:msg_var) >> iws? >> str(')')) |
        (str('(') >> iws? >> argdef.maybe.as(:args) >> iws? >> str(')'))
      }

      rule(:const) {
        nil_const | undef_const | true_const | false_const | integer_const | protocol_id_const |
        message_id_const | string_const | list_const
      }

      rule(:func) {
        (
          argdef_list >> iws? >> 
          (str("->") >> iws? >> local_var.as(:output_var) >> iws?).maybe >>
          statement_block.as(:func)
        )
      }

      rule(:prefix_op_expression) {
        ((str('!') | str('+') | str('-') | str('~')).as(:op) >> iws? >> call_expression).as(:prefix_op)
      }

      rule(:value_expression) {
        prefix_op_expression | const | func | variable |
        (str('(') >> iws? >> expression >> iws? >> str(')'))
      }

      rule(:args) {
        (iws? >> expression >> (iws? >> str(',') >> iws? >> expression).repeat).as(:args)
      }

      rule(:arglist) {
        str('(') >> iws? >> args.maybe >> iws? >> str(')')
      }

      rule(:line_statement) {
        statement >> eol
      }
      rule(:tail_statement) {
        statement >> iws?
      }
      rule(:statement_sequence) {
        ((ews? >> line_statement).repeat >> ews? >> tail_statement |
         (ews? >> line_statement).repeat(1) |
         ews? >> tail_statement |
         ews?).as(:sequence)
      }

      rule(:statement_block) {
        (ews? >> str("{") >> statement_sequence >> iws? >> str("}"))
      }

      rule(:member_invoke) {
        (lws? >> str('.') >> iws? >> method_name.as(:name) >> lws? >> arglist.maybe).as(:member_invoke)
      }
      rule(:array_access) {
        (lws? >> str('[') >> iws? >> expression >> iws? >> str(']')).as(:index_invoke)
      }
      rule(:value_invoke) {
        (lws? >> arglist).as(:value_invoke)
      }

      rule(:call_expression) {
        value_expression.as(:on) >> (member_invoke | array_access | value_invoke).repeat(1).as(:call) |
        value_expression
      }
      
      rule(:bytecode_instruction) {
        symbol.as(:instruction) >> (lws >> const).repeat.as(:args) >> lws?
      }

      rule(:bytecode_sequence) {
        (iws? >> bytecode_instruction >> eol).repeat(1) >> bytecode_instruction.maybe
      }

      rule(:bytecode_expression) {
        ((str("bytecode") >> lws? >> arglist.as(:input) >> iws? >> str('{') >> iws? >> bytecode_sequence.as(:bytecode) >> iws? >> str('}'))) |
        call_expression
      }

      rule(:product_op_expression) {
        bytecode_expression.as(:left) >> ((lws? >> (str('*') | str('/') | str('%')).as(:op) >> iws? >> bytecode_expression.as(:right)).repeat(1)).as(:product) |
        bytecode_expression
      }

      rule(:sum_op_expression) {
        product_op_expression.as(:left) >> ((lws? >> (str('+') | str('-')).as(:op) >> iws? >> product_op_expression.as(:right)).repeat(1)).as(:sum) |
        product_op_expression
      }

      rule(:bitshift_op_expression) {
        sum_op_expression.as(:left) >> ((lws? >> (str('>>') | str('<<')).as(:op) >> iws? >> sum_op_expression.as(:right)).repeat(1)).as(:bitshift) |
        sum_op_expression
      }

      rule(:relational_op_expression) {
        bitshift_op_expression.as(:left) >> ((lws? >> (str('<=') | str('>=') | str('>') | str('<')).as(:op) >> iws? >> bitshift_op_expression.as(:right)).repeat(1)).as(:relational) |
        bitshift_op_expression
      }

      rule(:equality_op_expression) {
        relational_op_expression.as(:left) >> ((lws? >> (str('==') | str('!=')).as(:op) >> iws? >> relational_op_expression.as(:right)).repeat(1)).as(:equality) |
        relational_op_expression
      }

      rule(:bitwise_op_expression) {
        equality_op_expression.as(:left) >> ((lws? >> (str('&') | str('^') | str('|')).as(:op) >> iws? >> equality_op_expression.as(:right)).repeat(1)).as(:bitwise) |
        equality_op_expression
      }

      rule(:logical_op_expression) {
        bitwise_op_expression.as(:left) >> ((lws? >> (str('&&') | str('||')).as(:op) >> iws? >> bitwise_op_expression.as(:right)).repeat(1)).as(:logical) |
        bitwise_op_expression
      }

      rule(:assignment_expression) {
        asgn_ops = (str('=') | str('+=') | str('-=') | str('*=') | str('/=') | str('%=') | str('&=') | str('^=') | str('|=') | str('<<=') | str('>>=')).as(:op)
        ((local_var.as(:assign_to) >> lws? >> asgn_ops >> iws?).repeat(1).as(:left)) >> logical_op_expression.as(:assign) |
        logical_op_expression
      }

      rule(:send_expression) {
        (assignment_expression.as(:send) >> lws? >> str("->") >> iws? >> assignment_expression.as(:target) >> (iws? >> str(":") >> iws? >> variable.as(:continuation)).maybe) |
        assignment_expression
      }

      rule(:return_expression) {
        (value_expression.as(:target) >> lws? >> str("<-") >> iws? >> send_expression.as(:return)) |
        send_expression
      }

      rule(:else_expression) {
        (str("else") >> lws? >> if_expression) |
        (str("else") >> lws? >> statement_block)
      }
      rule(:if_expression) {
        (str("if") >> lws? >> str("(") >> iws? >> expression.as(:if) >> iws? >> str(")")) >>
         iws? >> statement_block.as(:block) >>
         lws? >> else_expression.as(:else).maybe
      }
      rule(:while_expression) {
        (str("while") >> lws? >> str("(") >> iws? >> expression.as(:while) >> iws? >> str(")")) >>
         iws? >> statement_block.as(:block)
      }
      rule(:cases) {
        (lws? >> str("case") >> iws? >> str("(") >> iws? >> const.as(:case) >> iws? >> str(")") >> iws? >> statement_block.as(:block)).repeat(1).as(:cases) >> lws? >> else_expression.maybe
      }
      rule(:switch_expression) {
        (str("switch") >> lws? >> str("(") >> iws? >> expression.as(:switch) >> iws? >> str(")") >> iws? >> cases)
      }

      rule(:conditional_expression) {
        if_expression |
        while_expression |
        switch_expression |
        return_expression
      }

      rule(:expression) {
        conditional_expression
      }

      rule(:statement) {
        ((ews | comment).repeat.as(:doc) >> ws? >> expression.as(:expr)).as(:statement)
      }

      rule(:script) {
        statement_sequence.as(:script) >> iws?
      }

      root(:script)
    end
  end
end