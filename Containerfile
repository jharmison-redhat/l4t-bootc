FROM registry.redhat.io/rhel9/rhel-bootc:9.4

# Perform some basic package installation
COPY overlays/auth/ /
RUN --mount=type=tmpfs,target=/var/cache --mount=type=cache,id=dnf-cache,target=/var/cache/dnf \
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm && \
    dnf -y install tmux curl lm_sensors btop

# Enable L4T/Jetpack 6 on the AGX Orin
# TODO: Uncomment these when it works again
#COPY overlays/nvidia/ /
#RUN --mount=type=tmpfs,target=/var/cache --mount=type=cache,id=dnf-cache,target=/var/cache/dnf \
#    dnf -y install \
#    nvidia-container-toolkit-base \
#    nvidia-jetpack-all \
#    nvidia-jetpack-kmod \
#    nvtop

# Basic user configuration with nss-altfiles
COPY overlays/users/ /
