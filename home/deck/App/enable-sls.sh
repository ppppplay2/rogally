#!/bin/sh

echo "正在启用 SLS 并重启 Steam..."

systemctl --user set-environment LD_AUDIT="/usr/lib32/libSLSsteam.so"

systemd-run --user --unit=clear-ldaudit /bin/sh -c '
    pidwait -x steam
    until pgrep -x steam >/dev/null 2>&1; do
        sleep 0.05
    done
    systemctl --user unset-environment LD_AUDIT
'

systemctl --user restart gamescope-session.target

