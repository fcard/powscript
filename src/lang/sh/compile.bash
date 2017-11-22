powscript_source lang/sh/interactive.bash #<<EXPAND>>

sh:compile() { #<<NOSHADOW>>
  local expr="$1" out="$2"
  local expr_head

  ast:from $expr head expr_head

  case "$expr_head" in
    name)
      ast:from $expr value "$out"
      ;;

    string)
      local string
      ast:from $expr value string
      setvar "$out" "'$string'"
      ;;

    cat)
      local child compiled result=""
      ast:from $expr children expr_children
      for child in $expr_children; do
        backend:compile $child compiled
        result="$result$compiled"
      done
      setvar "$out" "$result"
      ;;

    assign)
      local var_ast value_ast
      local var value

      ast:children $expr var_ast value_ast

      backend:compile $var_ast   var
      backend:compile $value_ast value


      setvar "$out" "$var=$value"
      ;;

    math-assigned)
      local value_ast value

      ast:from $expr children value_ast

      NO_QUOTING=true backend:compile $value_ast value

      setvar "$out" "\$(( $value ))"
      ;;

    call)
      local children arg_ast
      local result cmd arg

      ast:from $expr children children
      children=( $children )

      backend:compile ${children[0]} cmd

      result="$cmd"
      for arg_ast in "${children[@]:1}"; do
        backend:compile $arg_ast arg
        result="$result $arg"
      done
      setvar "$out" "$result"
      ;;

    command-substitution)
      local call_ast call

      ast:from $expr children call_ast

      backend:compile $call_ast call

      if ast:is $call_ast math-top; then
        setvar "$out" "${call:5}"
      else
        if ${NO_QUOTING-false}; then
          setvar "$out" "\$( $call )"
        else
          setvar "$out" "\"\$( $call )\""
        fi
      fi
      ;;

    if|elif)
      local condition block after
      backend:compile-children $expr condition block after

      setvar "$out" "$expr_head $condition; then"$'\n'"${block:2:-2}"$'\n'"$after"
      ;;

    else)
      local block
      backend:compile-children $expr block

      setvar "$out" "else"$'\n'"${block:2:-2}"$'\n'"fi"
      ;;

    end_if)
      setvar "$out" "fi"
      ;;

    for)
      local varname
      local elements block

      ast:from $expr value varname
      backend:compile-children $expr elements block

      setvar "$out" "for $varname in $elements; do"$'\n'"${block:2:-2}"$'\ndone'
      ;;

    while)
      local condition block
      backend:compile-children $expr condition block

      setvar "$out" "while $condition; do"$'\n'"${block:2:-2}"$'\ndone'
      ;;
    switch)
      local value cases
      backend:compile-children $expr value cases

      setvar "$out" "case $value in"$'\n'"${cases:2:-2}"$'\n'"esac"
      ;;

    case)
      local pattern block
      backend:compile-children $expr pattern block

      setvar "$out" "$pattern)"$'\n'"${block:2:-2}"$'\n;;'
      ;;

    elements)
      local e elements r result

      ast:from $expr children elements

      for e in $elements; do
        backend:compile $e r
        result="$result$r "
      done

      setvar "$out" "${result:0:-1}"
      ;;

    simple-substitution)
      local name
      ast:from $expr value name

      if ${NO_QUOTING-false}; then
        setvar "$out" "\${$name}"
      else
        setvar "$out" "\"\${$name}\""
      fi
      ;;

    math-float)
      local precision child_ast child

      ast:from $expr value precision
      ast:from $expr children child_ast
      NO_QUOTING=true FLOAT_MATH=true backend:compile $child_ast child

      setvar "$out" "echo \"{scale=$precision; $child}\" | bc"
      ;;
    math-top)
      local child_ast child

      ast:from $expr children child_ast
      NO_QUOTING=true backend:compile $child_ast child

      setvar "$out" "echo \$(( $child ))"
      ;;

    math)
      local left_ast right_ast op
      local left right

      ast:all-from $expr -v op -@ left_ast right_ast

      if [ "$op" = "^" ] && ! ${FLOAT_MATH-false}; then
        case $PowscriptBackend in
          sh)
            backend:error "unimplemented: ^ operator in math"
            return
            ;;
          bash)
            op="**"
            ;;
        esac
      fi

      backend:compile $left_ast left

      if [ -n "$right_ast" ]; then
        backend:compile $right_ast right
        setvar "$out" "$left$op$right"
      else
        setvar "$out" "$op$left"
      fi
      ;;

    function-def)
      local name_ast args_ast block_ast
      local name args_ast arg_assign_ast argval_ast block_ast block
      local args arg argval argnum locals_ast argname_ast


      ast:children $expr name_ast args_ast block_ast

      sh:compile $name_ast name

      ast:make locals_ast local

      ast:from $args_ast children args

      argnum=1
      for arg in $args; do
        ast:make argval_ast simple-substitution $argnum
        ast:make arg_assign_ast assign '' $arg $argval_ast
        ast:push-child $locals_ast $arg_assign_ast
        argnum=$((argnum+1))
      done
      ast:unshift-child $block_ast $locals_ast

      sh:compile $block_ast block

      setvar "$out" "$name() $block"
      ;;

    local)
      local result="local" child_ast child
      ast:from $expr children expr_children

      for child_ast in $expr_children; do
        sh:compile $child_ast child
        result="$result $child"
      done

      setvar "$out" "$result"
      ;;

    block)
      local child_ast child result
      ast:from $expr children expr_children

      result='{'
      for child_ast in $expr_children; do
        backend:compile $child_ast child
        result="$result"$'\n'"$child"
      done
      result="$result"$'\n}'

      setvar "$out" "$result"
      ;;

    pattern)
      ast:from $expr value "$out"
      ;;

    condition)
      local op left right quoted=no
      ast:from $expr value op
      ast:from $expr children expr_children
      expr_children=( $expr_children )

      case "$op" in
        command)
          sh:compile ${expr_children[0]} left
          setvar "$out" "$left"
          ;;
        not)
          sh:compile ${expr_children[0]} right
          setvar "$out" "! $right"
          ;;
        -*)
          bash:compile ${expr_children[0]} right
          setvar "$out" "[ $op $right ]"
          ;;
        *)
          sh:compile ${expr_children[0]} left
          sh:compile ${expr_children[1]} right

          case "$op" in
            'is'|'=')     op='='    quoted=single ;;
            'isnt'|'!=')  op='!='   quoted=single ;;
            '==')         op='-eq'  quoted=single ;;
            '>')          op='-gt'  quoted=single ;;
            '>=')         op='-ge'  quoted=single ;;
            '<')          op='-lt'  quoted=single ;;
            '<=')         op='-le'  quoted=single ;;
            'and'|'&&')   op='&&' ;;
            'or'|'||')    op='||' ;;
            *) backend:error "unimplemented: condition: $op" ;;
          esac

          case $quoted in
            single) setvar "$out"  "[ $left $op $right ]"  ;;
            no)     setvar "$out"    "$left $op $right"    ;;
          esac
          ;;
      esac
      ;;
    newline|eof|'')
      ;;
    *)
      backend:error "unimplemented: '$expr_head'"
      ;;
  esac
}
noshadow sh:compile 1
