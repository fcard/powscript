declare -gA States

States[index]=0

push_state() {
  States[${States[index]}]=$1
  States[index]=$((${States[index]}+1))
}

pop_state() {
  local index=$((${States[index]}-1))
  States[index]=$index
  setvar "$1" ${States[$index]}
}

in_topmost_state() {
  [ ${States[index]} = 1 ]
}

clear_states() {
  unset States
  declare -gA States
  States[index]=0
  push_state top
}

push_state top
