OS = $(shell uname -s)
ARCH := x86
BUILD_DIR := build
BUILD_ABS_DIR := $(CURDIR)/$(BUILD_DIR)
VBOX_VM_NAME := bare-metal-gophers

kernel_target :=$(BUILD_DIR)/kernel-$(ARCH).bin
iso_target := $(BUILD_DIR)/kernel-$(ARCH).iso

export SHELL := /bin/bash -o pipefail

LD := ld
AS := nasm

GOOS := linux
GOARCH := 386

LD_FLAGS := -n -melf_i386 -T arch/$(ARCH)/script/linker.ld -static --no-ld-generated-unwind-info
AS_FLAGS := -g -f elf32 -F dwarf -I arch/$(ARCH)/asm/

asm_src_files := $(wildcard arch/$(ARCH)/asm/*.s)
asm_obj_files := $(patsubst arch/$(ARCH)/asm/%.s, $(BUILD_DIR)/arch/$(ARCH)/asm/%.o, $(asm_src_files))

kernel: $(kernel_target)

$(kernel_target): $(asm_obj_files) go.a
	@echo "[$(LD)] linking kernel-$(ARCH).bin"
	@$(LD) $(LD_FLAGS) -o $(kernel_target) $(asm_obj_files) $(BUILD_DIR)/go.a

go.a:
	@mkdir -p $(BUILD_DIR)

	@echo "[go] compiling go kernel sources into a standalone .o file"
	@GOARCH=$(GOARCH) GOOS=$(GOOS) go build -ldflags='-buildmode=c-archive' -o $(BUILD_DIR)/go.a

	@# build/go.a contains an elf32 object file but all Go symbols are unexported. Our
	@# asm entrypoint code needs to know the address to 'main.main' and 'runtime.g0'
	@# so we use objcopy to globalize them
	@echo "[objcopy] globalizing symbols {runtime.g0, main.main} in go.a"
	@objcopy \
		--globalize-symbol runtime.g0 \
		--globalize-symbol main.main \
		$(BUILD_DIR)/go.a $(BUILD_DIR)/go.a

$(BUILD_DIR)/arch/$(ARCH)/asm/%.o: arch/$(ARCH)/asm/%.s
	@mkdir -p $(shell dirname $@)
	@echo "[$(AS)] $<"
	@$(AS) $(AS_FLAGS) $< -o $@

iso: $(iso_target)

$(iso_target): $(kernel_target)
	@echo "[grub] building ISO kernel-$(ARCH).iso"

	@mkdir -p $(BUILD_DIR)/isofiles/boot/grub
	@cp $(kernel_target) $(BUILD_DIR)/isofiles/boot/kernel.bin
	@cp arch/$(ARCH)/script/grub.cfg $(BUILD_DIR)/isofiles/boot/grub
	@grub-mkrescue -o $(iso_target) $(BUILD_DIR)/isofiles 2>&1 | sed -e "s/^/  | /g"
	@rm -r $(BUILD_DIR)/isofiles

.PHONY: kernel iso run-qemu run-vbox gdb clean

run-qemu: iso
	qemu-system-i386 -cdrom $(iso_target)

run-vbox: iso
	VBoxManage createvm --name $(VBOX_VM_NAME) --ostype "Linux_64" --register || true
	VBoxManage storagectl $(VBOX_VM_NAME) --name "IDE Controller" --add ide || true
	VBoxManage storageattach $(VBOX_VM_NAME) --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive \
		--medium $(iso_target) || true
	VBoxManage setextradata $(VBOX_VM_NAME) GUI/ScaleFactor 2
	VBoxManage startvm $(VBOX_VM_NAME)

gdb: iso
	qemu-system-i386 -s -S -cdrom $(iso_target) &
	sleep 1
	gdb \
	    -ex "add-auto-load-safe-path $(pwd)" \
	    -ex "file $(kernel_target)" \
	    -ex "set disassembly-flavor intel" \
	    -ex 'set arch i386:intel' \
	    -ex 'target remote localhost:1234' \
	    -ex 'layout asm' \
	    -ex 'b _rt0_entry' \
	    -ex 'continue' \
	    -ex 'disass'
	@killall qemu-system-i386 || true

clean:
	@test -d $(BUILD_DIR) && rm -rf $(BUILD_DIR) || true
