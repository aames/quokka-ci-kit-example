
case "$job" in
@@CASES@@
  *) refuse "There is no job named ${job:-(none)}, so nothing ran." ;;
esac
