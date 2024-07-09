---
variant: fcos
version: 1.5.0
storage:
  files:
    - path: /etc/ostree/auth.json
      contents:
        inline: |-
          ${AUTH}
      mode: 0644
    - path: /var/home/core/.bashrc
      append:
        - inline: tmux new-session -d 'sudo journalctl -f' \; attach
systemd:
  units:
    - name: getty@tty1.service
      dropins:
        - name: autologin.conf
          contents: |
            [Service]
            ExecStart=
            ExecStart=-/usr/sbin/agetty -o '-p -f -- \\u' --autologin core --noclear %I $TERM
    - name: install.service
      enabled: true
      contents: |
        [Unit]
        Description=Install a bootc image to the disk
        After=network-online.target systemd-hostnamed.service
        Wants=network-online.target systemd-hostnamed.service
        [Service]
        User=root
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=/usr/bin/podman run --authfile /etc/ostree/auth.json --rm --privileged --pid=host -v /var/lib/containers:/var/lib/containers -v /etc/ostree:/etc/ostree -v /dev:/dev --security-opt label=type:unconfined_t ${BASE} bootc install to-disk --wipe /dev/${DISK} --target_imgref ${IMAGE}
        [Install]
        WantedBy=multi-user.target
