
#!/bin/bash
exec > /tmp/phrog.log 2>&1
export XDG_CURRENT_DESKTOP=Phrog:Phosh:GNOME
export GNOME_SESSION_AUTOSTART_DIR=/usr/share/phrog/autostart:/etc/phrog/autostart
export WLR_RENDERER=pixman
export WLR_RENDERER_ALLOW_SOFTWARE=1
export GSK_RENDERER=cairo
export LIBGL_ALWAYS_SOFTWARE=1
PHOC_INI=/etc/phrog/phoc.ini
[ ! -f $PHOC_INI ] && PHOC_INI=/usr/share/phrog/phoc.ini
[ ! -f $PHOC_INI ] && PHOC_INI=/etc/phosh/phoc.ini
[ ! -f $PHOC_INI ] && PHOC_INI=/usr/share/phosh/phoc.ini
echo "using $PHOC_INI"
env | grep -E "WLR|GSK|LIBGL|XDG"
exec dbus-run-session phoc -S -C "$PHOC_INI" -E 'gnome-session --session=phrog'
