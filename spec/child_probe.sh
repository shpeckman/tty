# spec/child_probe.sh
sid=$(ps -o sess= -p $$ 2>/dev/null | tr -d ' ')
[ -z "$sid" ] && sid=$(ps -o sid= -p $$ 2>/dev/null | tr -d ' ')
echo "SID=${sid} PID=$$"
if { : < /dev/tty ; } 2>/dev/null; then echo "HAS_CTTY=yes"; else echo "HAS_CTTY=no"; fi
echo "TTYNAME=$(tty 2>/dev/null)"
exit 0