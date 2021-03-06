declare -gA Asts

Asts[index]=0
Asts[length]=0
Asts[required-indent]=0

powscript_source ast/indent.bash #<<EXPAND>>
powscript_source ast/states.bash #<<EXPAND>>

ast:new() { #<<NOSHADOW>>
  local index="${Asts[index]}"
  local length="${Asts[length]}"

  setvar "$1" "$index"

  Asts[head-$index]=
  Asts[value-$index]=
  Asts[children-$index]=

  if [ ! $index = $length ]; then
    Asts[index]=$(($index+1))
  else
    Asts[index]=$(($length+1))
  fi
  Asts[length]=$(($length+1))
}
noshadow ast:new

ast:make() {
  local __newast __newchild
  ast:new __newast
  ast:set "$__newast" head  "$2"
  ast:set "$__newast" value "$3"
  for __newchild in ${@:4}; do
    ast:push-child "$__newast" $__newchild
  done
  setvar "$1" "$__newast"
}

ast:make-from-string() {
  local __mkstr_out
  ast:_make-from-string __mkstr_out "$2"
  setvar "$1" "$__mkstr_out"
}

ast:_make-from-string() {
  local out="$1" string="$2"
  local ast child
  local trimmed incomplete_marker marker_head marker info head value
  declare -a children

  while IFS="" read -r line; do
    trimmed="${line#${line%%[^" "]*}}"
    incomplete_marker="${trimmed%%[^-]*}"
    marker_head="${trimmed:${#incomplete_marker}:1}"
    if [[ ! "$marker_head" = '+' ]]; then
      marker_head=""
    fi
    marker="$incomplete_marker$marker_head"
    info="${trimmed#$marker}"
    info="${info#${info%%[^" "]*}}"

    case "$marker" in
      *+)
        ast="$info"
        ;;
      *)
        head="${info%% *}"
        if [ -n "$head" ]; then
          value="${info#*$head}"
          value="${value# }"
          ast:make ast $head "$value"
          children[${#marker}]=$ast
        fi
        ;;
    esac
    if [ ${#marker} -gt 0 ]; then
      ast:push-child ${children[${#marker}-1]} "$ast"
    fi
  done <<<"$string"
  setvar "$out" "${children[0]}"
}

ast:from() {
  setvar "$3" "${Asts["$2-$1"]}"
}

ast:all-from() {
  local __af_expr="$1"
  shift

  while [ $# -gt 0 ]; do
    case "$1" in
      -e|--expr)
        setvar "$2" $__af_expr
        shift 2
        ;;
      -v|--value)
        ast:from $__af_expr value "$2"
        shift 2
        ;;
      -h|--head)
        ast:from $__af_expr head "$2"
        shift 2
        ;;
      -c|--children)
        ast:from $__af_expr children "$2"
        shift 2
        ;;
      -@|--@children)
        ast:children $__af_expr "${@:2}"
        shift $#
        ;;
      *)
        ast:error "Invalid flag $1, expected -[evhc@]"
        ;;
    esac
  done
}

ast:set() {
  Asts["$2-$1"]="$3"
}

ast:is() {
  local ast_head ast_value res=false
  ast:from $1 head  ast_head
  ast:from $1 value ast_value

  case $# in
    2) case $ast_head  in $2) res=true ;; esac
       ;;
    3) case $ast_head  in $2)
       case $ast_value in $3) res=true ;; esac ;; esac
       ;;
  esac
  $res
}


ast:push-child() {
  Asts["children-$1"]="${Asts["children-$1"]} $2"
}

ast:unshift-child() {
  Asts["children-$1"]="$2 ${Asts["children-$1"]}"
}

ast:shift-child() {
  setvar "$2" "${Asts["children-$1"]%% *}"
  Asts["children-$1"]="${Asts["children-$1"]#* }"
}

ast:pop-child() {
  setvar "$2" "${Asts["children-$1"]##* }"
  Asts["children-$1"]="${Asts["children-$1"]% *}"
}

ast:children() { #<<NOSHADOW>>
  local ast="$1"
  local ast_children children_array child i

  ast:from $ast children ast_children
  children_array=( $ast_children )

  i=0
  for child_name in ${@:2}; do
    setvar "$child_name" ${children_array[$i]}
    i=$((i+1))
  done
}
noshadow ast:children 1 @


ast:clear() {
  unset Asts["value-$1"]
  unset Asts["head-$1"]
  unset Asts["children-$1"]
}

ast:clear-all() {
  unset Asts
  declare -gA Asts

  Asts[index]=0
  Asts[length]=0
  Asts[required-indent]=0
}

