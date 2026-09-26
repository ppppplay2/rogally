#!/bin/bash
set -e

systemd-run --user --quiet --collect /bin/bash -c '
    set -e

    d="$XDG_RUNTIME_DIR/systemd/user/steam-launcher.service.d"
    f="$d/sls.conf"

    cleanup() { rm -rf "$d"; systemctl --user daemon-reload; }
    trap cleanup EXIT INT TERM

    mkdir -p "$d"
    cat > "$f" << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/env LD_AUDIT=/usr/lib32/libSLSsteam.so /usr/lib/steamos/steam-launcher
ExecStartPre=
ExecStopPost=
EOF

    systemctl --user daemon-reload
    systemctl --user restart steam-launcher.service
'
