powscript_source ast/helper.bash       #<<EXPAND>>
powscript_source ast/expand.bash       #<<EXPAND>>
powscript_source ast/sequence.bash     #<<EXPAND>>
powscript_source ast/expressions.bash  #<<EXPAND>>
powscript_source ast/math.bash         #<<EXPAND>>
powscript_source ast/commands.bash     #<<EXPAND>>
powscript_source ast/blocks.bash       #<<EXPAND>>
powscript_source ast/patterns.bash     #<<EXPAND>>
powscript_source ast/conditionals.bash #<<EXPAND>>
powscript_source ast/functions.bash    #<<EXPAND>>
powscript_source ast/parallel.bash     #<<EXPAND>>
powscript_source ast/lowerer.bash      #<<EXPAND>>
powscript_source ast/print.bash        #<<EXPAND>>

# ast:parse:try
#
# Try parsing an ast expression from the input,
# printing 'top' on success or the last
# parser state on failure.

ast:parse:try() {
  (
    local ast
    POWSCRIPT_INCOMPLETE_STATE=

    trap '
      if [ -n "$POWSCRIPT_INCOMPLETE_STATE" ]; then
        echo "$POWSCRIPT_INCOMPLETE_STATE"
      else
        ast:last-state
      fi
      exit' EXIT

    POWSCRIPT_ALLOW_INCOMPLETE=true ast:parse ast
    exit
  )
}


# ast:parse $out
#
# Parse an ast expression from the input,
# storing it in $out.

ast:parse() {
  ast:parse:linestart "$1"
}


# ast:parse:linestart $out
#
# Test that there is no indentation before proceeding
# to parse the expression.

ast:parse:linestart() { #<<NOSHADOW>>
  local value class line

  token:get -v value -c class -ls line

  if [ "$class" = whitespace ]; then
    ast:error "indentation error at line $line, unexpected indentation of $value."
  else
    token:backtrack
    ast:parse:top "$1"
  fi
}
noshadow ast:parse:linestart


# ast:parse:top $out
#
# Analyze first expression and dispatch to the
# appropriate function appropriate for it.

ast:parse:top() { #<<NOSHADOW>>
  local out="$1"
  local expr expr_head assigns

  ast:parse:expr expr
  ast:from $expr head expr_head

  case $expr_head in
    name)
      local expr_value
      ast:from $expr value expr_value
      case "$expr_value" in
        'if')      ast:parse:if 'if' "$out" ;;
        'for')     ast:parse:for     "$out" ;;
        'case')    ast:parse:case    "$out" ;;
        'math')    ast:parse:math    "$out" ;;
        'while')   ast:parse:while   "$out" ;;
        'switch')  ast:parse:switch  "$out" ;;
        'await')   ast:parse:await   "$out" ;;
        'require') ast:parse:require "$out" ;;
        'expand')  ast:parse:expand  "$out" ;;
        'declare')
          local type_ast type

          ast:parse:specific-expr name type_ast
          ast:from $type_ast value type

          ast:make "$out" declare
          ast:set "${!out}" value $type
          ast:parse:sequence "${!out}" 'ast:is % name'
          ;;
        *)
          if token:next-is special '('; then
            ast:parse:function-definition $expr "$out"
          else
            ast:make assigns assign-sequence
            ast:parse:command-call-with-cmd $assigns $expr "$out"
          fi
          ;;
      esac
      ;;
    *assign)
      ast:parse:assign-sequence $expr "$out"
      ;;
    newline)
      setvar "$out" -1
      ;;
    *)
      ast:make assigns assign-sequence
      ast:parse:command-call-with-cmd $assigns $expr "$out"
      ;;
  esac
}
noshadow ast:parse:top
