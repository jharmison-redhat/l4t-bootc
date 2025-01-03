RUNTIME ?= podman

RHEL_VERSION ?= 9.4
REGISTRY ?= registry.jharmison.com
REPOSITORY ?= l4t/image
TAG ?= latest
REG_REPO := $(REGISTRY)/$(REPOSITORY)
IMAGE = $(REG_REPO):$(TAG)
BASE ?= registry.redhat.io/rhel9/rhel-bootc:$(RHEL_VERSION)
LATEST_DIGEST := $(shell hack/latest_base.sh $(BASE) arm64)

# Vars only for building the kickstart-based installer
DEFAULT_INSTALL_DISK ?= mmcblk0
BOOT_VERSION ?= $(RHEL_VERSION)
ISO_SUFFIX ?=
# ISO_DEST is the device to burn the iso to (such as a USB flash drive for live booting the installer on metal)
ISO_DEST ?= /dev/sda
# NETWORK defines the kickstart arguments for configuring the network, defaulting to DHCP on wired links
NETWORK := --bootproto=dhcp --device=link --activate
TZ := America/New_York
# Templating the kickstart variables is tricky
KICKSTART_VARS = IMAGE=$(IMAGE) \
	DEFAULT_DISK=$(DEFAULT_INSTALL_DISK) \
	NETWORK="$(NETWORK)" \
	TZ=$(TZ) \
	ROOT_SSH_KEY="$(shell cat overlays/users/usr/local/ssh/core.keys 2>/dev/null)"


.PHONY: all
all: .push

overlays/users/usr/local/ssh/core.keys:
	@if [ -e "$@" ]; then touch "$@"; else echo "Please put the authorized_keys file you would like for the core user in $@" >&2; exit 1; fi

overlays/auth/etc/ostree/auth.json:
	@if [ -e "$@" ]; then touch "$@"; else echo "Please put the auth.json for your registry $(REGISTRY)/$(REPOSITORY) in $@" >&2; exit 1; fi

boot-image/rhel-$(RHEL_VERSION)-aarch64-boot.iso:
	@if [ -e "$@" ]; then touch "$@"; else echo "Please download the RHEL boot ISO from https://access.redhat.com/downloads/content/419/ver=/rhel---9/9.4/aarch64/product-software to place in $@" >&2; exit 1; fi

tmp/$(LATEST_DIGEST):
	@touch $@

.build: Containerfile overlays/auth/etc/ostree/auth.json overlays/users/usr/local/ssh/core.keys $(shell find overlays -type f) tmp/$(LATEST_DIGEST)
	$(RUNTIME) build --security-opt label=disable --arch aarch64 --pull=newer --cap-add=all --device=/dev/fuse --from $(BASE) . -t $(IMAGE)
	@touch $@

.PHONY: build
build: .build

.push: .build
	$(RUNTIME) push $(IMAGE)
	@touch $@

.PHONY: push
push: .push

.PHONY: debug
debug:
	$(RUNTIME) run --rm -it --arch aarch64 --pull=never --entrypoint /bin/bash -v /var/tmp/buildah-cache-$$UID/8a2a6a29aeebc33c:/var/cache/dnf $(IMAGE) -li

boot-image/bootc$(ISO_SUFFIX).ks: boot-image/bootc.ks.tpl
	$(KICKSTART_VARS) envsubst '$$IMAGE,$$DEFAULT_DISK,$$NETWORK,$$TZ,$$ROOT_SSH_KEY' < $< >$@

boot-image/container/index.json: .build
	rm -rf boot-image/container
	skopeo copy containers-storage:$(IMAGE) oci:boot-image/container

boot-image/bootc-install$(ISO_SUFFIX).iso: boot-image/bootc$(ISO_SUFFIX).ks boot-image/container/index.json boot-image/rhel-$(RHEL_VERSION)-aarch64-boot.iso boot-image/container/index.json
	@if [ -e $@ ]; then rm -f $@; fi
	sudo skopeo copy oci:boot-image/container containers-storage:$(IMAGE)
	sudo $(RUNTIME) run --rm -it --security-opt=label=disable --arch aarch64 --pull=never --cap-add=all --privileged --device=/dev/fuse --entrypoint bash -v /var/tmp/buildah-cache-$$UID/8a2a6a29aeebc33c:/var/cache/dnf -v $$PWD:/workdir --workdir /workdir $(IMAGE) -c 'dnf -y install lorax; mkksiso --add boot-image/container --ks $< boot-image/rhel-$(RHEL_VERSION)-aarch64-boot.iso $@'

.PHONY: iso
iso: boot-image/bootc-install$(ISO_SUFFIX).iso

.PHONY: burn
burn: boot-image/bootc-install$(ISO_SUFFIX).iso
	sudo dd if=./$< of=$(ISO_DEST) bs=1M conv=fsync status=progress

.PHONY: clean
clean:
	rm -rf .build* .push* boot-image/bootc-install.iso boot-image/*.ks boot-image/container
	buildah prune -af

.PHONY: list
list:
	@LC_ALL=C $(MAKE) -pRrq -f $(firstword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/(^|\n)# Files(\n|$$)/,/(^|\n)# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | grep -E -v -e '^[^[:alnum:]]' -e '^$@$$'

tmp/firmware.tbz2:
	curl -Lo $@ https://developer.nvidia.com/downloads/igx/v1.0.0/jetson_linux_r36.3.1_aarch64.tbz2

tmp/Linux_for_Tegra/flash.sh: tmp/firmware.tbz2
	rm -rf $(dir $@)
	tar xf $< -C ./tmp
	touch tmp/Linux_for_Tegra/flash.sh

tmp/.venv/bin/pip: hack/firmware-requirements.txt
	rm -rf tmp/.venv
	python3 -m venv tmp/.venv
	tmp/.venv/bin/pip install setuptools wheel
	tmp/.venv/bin/pip install -r hack/firmware-requirements.txt

.PHONY: write-firmware
write-firmware: tmp/.venv/bin/pip tmp/Linux_for_Tegra/flash.sh
	hack/update-firmware.sh
