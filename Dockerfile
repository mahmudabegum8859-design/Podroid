# ─────────────────────────────────────────────────────────────────────────────
# Podroid Unified Dockerfile
# Combines Custom Kernel, Initramfs (Alpine VM) and QEMU (Android ARM64) builds.
# ─────────────────────────────────────────────────────────────────────────────

# ==============================================================================
# SECTION 0: Custom Kernel Build (aarch64) — Image + modules
# ==============================================================================
FROM debian:bookworm AS kernel-builder
ARG KERNEL_VERSION=7.0.10
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget ca-certificates xz-utils make gcc gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    bc bison flex libssl-dev libelf-dev python3 kmod cpio \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN wget -q https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${KERNEL_VERSION}.tar.xz \
    && tar xf linux-${KERNEL_VERSION}.tar.xz \
    && rm linux-${KERNEL_VERSION}.tar.xz

COPY podroid_kernel.config /tmp/podroid_kernel.config
# Force-builtin fragment: options netavark + podman need as =y so there's no
# modprobe round-trip (modules caused silent failures in the past). Applied
# WITHOUT -m on top of the main fragment, then locked in with olddefconfig.
RUN printf '%s\n' \
    'CONFIG_IPV6=y' \
    'CONFIG_BRIDGE=y' \
    'CONFIG_BRIDGE_NETFILTER=y' \
    'CONFIG_BRIDGE_VLAN_FILTERING=y' \
    'CONFIG_VLAN_8021Q=y' \
    'CONFIG_STP=y' \
    'CONFIG_LLC=y' \
    'CONFIG_VETH=y' \
    'CONFIG_TUN=y' \
    'CONFIG_DUMMY=y' \
    'CONFIG_NETFILTER=y' \
    'CONFIG_NETFILTER_ADVANCED=y' \
    'CONFIG_NETFILTER_NETLINK=y' \
    'CONFIG_NF_CONNTRACK=y' \
    'CONFIG_NF_CT_NETLINK=y' \
    'CONFIG_NF_NAT=y' \
    'CONFIG_NF_TABLES=y' \
    'CONFIG_NF_TABLES_INET=y' \
    'CONFIG_NF_TABLES_IPV4=y' \
    'CONFIG_NF_TABLES_IPV6=y' \
    'CONFIG_NF_TABLES_BRIDGE=y' \
    'CONFIG_NFT_NAT=y' \
    'CONFIG_NFT_MASQ=y' \
    'CONFIG_NFT_CT=y' \
    'CONFIG_NFT_COMPAT=y' \
    'CONFIG_NF_NAT_MASQUERADE=y' \
    'CONFIG_IP_NF_IPTABLES=y' \
    'CONFIG_IP_NF_FILTER=y' \
    'CONFIG_IP_NF_NAT=y' \
    'CONFIG_IP_NF_TARGET_MASQUERADE=y' \
    'CONFIG_IP6_NF_IPTABLES=y' \
    'CONFIG_IP6_NF_FILTER=y' \
    'CONFIG_IP6_NF_NAT=y' \
    'CONFIG_IP6_NF_TARGET_MASQUERADE=y' \
    'CONFIG_NETFILTER_XTABLES=y' \
    'CONFIG_NETFILTER_XTABLES_LEGACY=y' \
    'CONFIG_IP_NF_IPTABLES_LEGACY=y' \
    'CONFIG_IP6_NF_IPTABLES_LEGACY=y' \
    'CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y' \
    'CONFIG_NETFILTER_XT_MATCH_CONNTRACK=y' \
    'CONFIG_NETFILTER_XT_MATCH_MARK=y' \
    'CONFIG_NETFILTER_XT_MATCH_COMMENT=y' \
    'CONFIG_NETFILTER_XT_TARGET_MASQUERADE=y' \
    'CONFIG_NETFILTER_XT_TARGET_REDIRECT=y' \
    'CONFIG_NETFILTER_XT_TARGET_MARK=y' \
    'CONFIG_OVERLAY_FS=y' \
    'CONFIG_FUSE_FS=y' \
    'CONFIG_EXT4_FS_SECURITY=y' \
    'CONFIG_SQUASHFS_XATTR=y' \
    'CONFIG_SQUASHFS_ZSTD=y' \
    'CONFIG_DECOMPRESS_ZSTD=y' \
    'CONFIG_ZSTD_DECOMPRESS=y' \
    'CONFIG_IKCONFIG=y' \
    'CONFIG_IKCONFIG_PROC=y' \
    'CONFIG_IP_NF_RAW=y' \
    'CONFIG_IP6_NF_RAW=y' \
    'CONFIG_BLK_DEV_THROTTLING=y' \
    'CONFIG_NET_CLS_CGROUP=y' \
    'CONFIG_CFS_BANDWIDTH=y' \
    'CONFIG_IP_NF_TARGET_REDIRECT=y' \
    'CONFIG_IP_SCTP=y' \
    'CONFIG_IP_VS=y' \
    'CONFIG_IP_VS_NFCT=y' \
    'CONFIG_IP_VS_PROTO_TCP=y' \
    'CONFIG_IP_VS_PROTO_UDP=y' \
    'CONFIG_IP_VS_RR=y' \
    'CONFIG_NFT_FIB=y' \
    'CONFIG_NFT_FIB_IPV4=y' \
    'CONFIG_NFT_FIB_IPV6=y' \
    'CONFIG_VXLAN=y' \
    'CONFIG_IPVLAN=y' \
    'CONFIG_MACVLAN=y' \
    'CONFIG_DUMMY=y' \
    'CONFIG_CRYPTO_GCM=y' \
    'CONFIG_CRYPTO_GHASH=y' \
    'CONFIG_CRYPTO_SEQIV=y' \
    'CONFIG_XFRM=y' \
    'CONFIG_XFRM_USER=y' \
    'CONFIG_XFRM_ALGO=y' \
    'CONFIG_INET_ESP=y' \
    'CONFIG_NETFILTER_XT_MATCH_BPF=y' \
    'CONFIG_NF_CONNTRACK_FTP=y' \
    'CONFIG_NF_NAT_FTP=y' \
    'CONFIG_NF_CONNTRACK_TFTP=y' \
    'CONFIG_NF_NAT_TFTP=y' \
    'CONFIG_BTRFS_FS=y' \
    'CONFIG_BTRFS_FS_POSIX_ACL=y' \
    'CONFIG_SECURITY_APPARMOR=y' \
    'CONFIG_IP6_NF_MANGLE=y' \
    'CONFIG_BINFMT_MISC=y' \
    'CONFIG_VSOCKETS=y' \
    'CONFIG_VSOCKETS_DIAG=y' \
    'CONFIG_VIRTIO_VSOCKETS=y' \
    > /tmp/forced_builtin.config
RUN cd linux-${KERNEL_VERSION} \
    && make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig \
    && ./scripts/kconfig/merge_config.sh -m .config /tmp/podroid_kernel.config \
    && ./scripts/kconfig/merge_config.sh -m .config /tmp/forced_builtin.config \
    && make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig \
    && echo "=== verifying critical options are =y ===" \
    && for opt in IPV6 BRIDGE BRIDGE_NETFILTER NF_TABLES_BRIDGE \
                  NETFILTER_XTABLES_LEGACY \
                  IP_NF_IPTABLES_LEGACY IP6_NF_IPTABLES_LEGACY \
                  IP6_NF_IPTABLES IP6_NF_FILTER IP6_NF_NAT \
                  IP_NF_TARGET_MASQUERADE IP6_NF_TARGET_MASQUERADE \
                  NETFILTER_XT_TARGET_MASQUERADE NF_NAT_MASQUERADE \
                  NFT_COMPAT NFT_MASQ NFT_NAT \
                  VETH TUN NF_TABLES NF_NAT NETFILTER OVERLAY_FS FUSE_FS \
                  EXT4_FS_SECURITY SQUASHFS_XATTR SQUASHFS_ZSTD \
                  DECOMPRESS_ZSTD ZSTD_DECOMPRESS \
                  IKCONFIG IKCONFIG_PROC BINFMT_MISC \
                  VSOCKETS VIRTIO_VSOCKETS \
                  RFKILL LEDS_CLASS CFG80211 MAC80211 RTW88 BT \
                  USB USB_SUPPORT WLAN \
                  RTW88_8821AU RTW88_8812AU RTW88_8814AU \
                  FW_LOADER_COMPRESS FW_LOADER_COMPRESS_ZSTD UNICODE \
                  USB_XHCI_HCD USB_XHCI_PCI USB_STORAGE USB_UAS \
                  SCSI BLK_DEV_SD VFAT_FS EXFAT_FS; do \
           grep -q "^CONFIG_${opt}=y\$" .config \
               || { echo "FATAL: CONFIG_${opt} is not =y after merge" >&2; \
                    grep "CONFIG_${opt}" .config >&2; exit 1; }; \
       done \
    && echo "=== all critical options are built-in ===" \
    && make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image.gz modules

RUN cd linux-${KERNEL_VERSION} \
    && make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
       INSTALL_MOD_PATH=/modules INSTALL_MOD_STRIP=1 modules_install \
    && rm -f /modules/lib/modules/*/build /modules/lib/modules/*/source
# Keep only modules init-podroid actually uses; everything else (DSA, pinctrl,
# mediatek, renesas, hardware-specific drivers) is dead weight in a VM.
# init-podroid runs `depmod -a` at boot so we don't need to regenerate modules.dep here.
RUN cd /modules/lib/modules/*/kernel \
    && find . -name '*.ko' | grep -vE '(^\./net/(bridge|netfilter|9p|ipv4/netfilter|ipv6/netfilter)/|^\./fs/(9p|fuse|overlayfs)/|^\./drivers/net/(tun|veth|virtio_net)\.ko|^\./drivers/block/virtio_blk\.ko|^\./drivers/char/hw_random/virtio-rng\.ko|^\./drivers/virtio/)' \
    | xargs rm -f \
    && find . -type d -empty -delete

RUN mkdir -p /output \
    && cp linux-${KERNEL_VERSION}/arch/arm64/boot/Image.gz /output/vmlinuz-virt

# ==============================================================================
# SECTION 1: Initramfs (Alpine VM) Build
# ==============================================================================

# Stage 1: Download Alpine aarch64 artifacts
FROM alpine:3.23 AS downloader
RUN apk add --no-cache wget cpio gzip tar xorriso
WORKDIR /downloads
RUN wget -q https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/aarch64/alpine-netboot-3.23.3-aarch64.tar.gz \
    && mkdir -p /netboot && tar -xf alpine-netboot-3.23.3-aarch64.tar.gz -C /netboot
RUN wget -q https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/aarch64/alpine-virt-3.23.3-aarch64.iso \
    && mkdir -p /iso && xorriso -osirrox on -indev alpine-virt-3.23.3-aarch64.iso -extract / /iso 2>/dev/null || true

# Stage 2: Build the custom rootfs (aarch64) — no linux-virt; modules come from kernel-builder
FROM --platform=linux/arm64/v8 alpine:3.23 AS rootfs-builder
RUN apk update && apk add --no-cache \
    bash busybox busybox-extras ttyd podman \
    netavark aardvark-dns fuse-overlayfs slirp4netns iptables ip6tables \
    shadow-uidmap ca-certificates crun curl e2fsprogs util-linux openrc \
    dropbear ncurses-terminfo-base musl-locales kmod fastfetch
COPY init-podroid /init
RUN chmod +x /init
RUN rm -rf /var/cache/apk/* /tmp/* /var/tmp/* /usr/share/man /usr/share/doc

# Stage 3: Pack Initramfs
FROM alpine:3.23 AS packer
RUN apk add --no-cache cpio gzip findutils
COPY --from=kernel-builder /output/vmlinuz-virt /output/vmlinuz-virt
COPY --from=rootfs-builder / /rootfs/
# Install kernel modules matching the custom kernel
COPY --from=kernel-builder /modules/lib/modules /rootfs/lib/modules
# Strip ephemeral dirs and boot dir
RUN rm -rf /rootfs/proc/* /rootfs/sys/* /rootfs/dev/* /rootfs/run/* \
           /rootfs/tmp/* /rootfs/boot
RUN cd /rootfs && find . | cpio -o -H newc 2>/dev/null | gzip -9 > /output/initrd.img

# ==============================================================================
# SECTION 2: QEMU & Bridge (Android multi-ABI) Build
# ==============================================================================

FROM debian:bookworm AS qemu-builder
ARG QEMU_VERSION=10.2.4
ARG ABI=arm64-v8a
ENV QEMU_DIR=qemu-${QEMU_VERSION}
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl unzip xz-utils ca-certificates git bzip2 ninja-build python3 python3-pip \
    pkg-config flex bison make cmake autoconf automake libtool libglib2.0-dev \
    libglib2.0-bin gettext libintl-perl binutils-aarch64-linux-gnu patchelf \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install --break-system-packages meson 2>/dev/null || pip3 install meson

# NDK
RUN wget -q https://dl.google.com/android/repository/android-ndk-r27c-linux.zip -O /tmp/ndk.zip \
    && unzip -q /tmp/ndk.zip -d /opt && mv /opt/android-ndk-r27c /opt/ndk && rm /tmp/ndk.zip
# ── Per-ABI toolchain selection ───────────────────────────────────────────────
# Writes /opt/abi.env, sourced by every RUN below, with $ABI-specific vars:
#   CLANG/TARGET    NDK clang wrapper + -target triple (API 26, our minSdk)
#   SYSROOT_LIBDIR  sysroot lib dir to seed with our static shims
#   CONFIG_HOST     autoconf --host triplet
#   MESON_CROSS     meson cross file for glib/pixman
#   UC_ARCH         libucontext arch (aarch64 / arm / x86_64)
#   QEMU_ALIGN      -Wl,-z,max-page-size=16384 on arm64 only (mandatory on
#                    Android 13+ 16KB-page devices; meaningless on 4KB 32-bit
#                    ARM / x86_64)
#   EXTRA_ATOMIC    -latomic on armv7 (Bionic 64-bit atomics live in a lib)
RUN case "$ABI" in \
      arm64-v8a) \
        echo 'export NDK=/opt/ndk' \
        && echo 'export LLVM=/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64' \
        && echo 'export PREFIX=/opt/deps' \
        && echo 'export CLANG=aarch64-linux-android26-clang' \
        && echo 'export TARGET=aarch64-linux-android26' \
        && echo 'export SYSROOT_LIBDIR=aarch64-linux-android' \
        && echo 'export CONFIG_HOST=aarch64-linux-android' \
        && echo 'export MESON_CROSS=/opt/cross-android-aarch64.ini' \
        && echo 'export PKGCONFIG=aarch64-android-pkg-config' \
        && echo 'export UC_ARCH=aarch64' \
        && echo 'export QEMU_ALIGN=-Wl,-z,max-page-size=16384' \
        && echo 'export EXTRA_ATOMIC=' \
        ;; \
      armeabi-v7a) \
        echo 'export NDK=/opt/ndk' \
        && echo 'export LLVM=/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64' \
        && echo 'export PREFIX=/opt/deps' \
        && echo 'export CLANG=armv7a-linux-androideabi26-clang' \
        && echo 'export TARGET=armv7a-linux-androideabi26' \
        && echo 'export SYSROOT_LIBDIR=arm-linux-androideabi' \
        && echo 'export CONFIG_HOST=arm-linux-androideabi' \
        && echo 'export MESON_CROSS=/opt/cross-android-armv7.ini' \
        && echo 'export PKGCONFIG=armv7-android-pkg-config' \
        && echo 'export UC_ARCH=arm' \
        && echo 'export QEMU_ALIGN=' \
        && echo 'export EXTRA_ATOMIC=-latomic' \
        ;; \
      x86_64) \
        # Intel/AMD Android (ChromeOS, emulators). 4KB pages, 64-bit atomics
        # live in libc. 32-bit x86 (i686) is not shipped — essentially no such
        # devices exist, and newer QEMU lines (11+) dropped 32-bit hosts; we
        # pin 10.2.x anyway so the armeabi-v7a build keeps working.
        echo 'export NDK=/opt/ndk' \
        && echo 'export LLVM=/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64' \
        && echo 'export PREFIX=/opt/deps' \
        && echo 'export CLANG=x86_64-linux-android26-clang' \
        && echo 'export TARGET=x86_64-linux-android26' \
        && echo 'export SYSROOT_LIBDIR=x86_64-linux-android' \
        && echo 'export CONFIG_HOST=x86_64-linux-android' \
        && echo 'export MESON_CROSS=/opt/cross-android-x86_64.ini' \
        && echo 'export PKGCONFIG=x86_64-android-pkg-config' \
        && echo 'export UC_ARCH=x86_64' \
        && echo 'export QEMU_ALIGN=' \
        && echo 'export EXTRA_ATOMIC=' \
        ;; \
      *) echo "FATAL: unsupported ABI '$ABI'" >&2; exit 1 ;; \
    esac > /opt/abi.env \
    && printf 'export CC="${LLVM}/bin/${CLANG}"\nexport AR="${LLVM}/bin/llvm-ar"\nexport RANLIB="${LLVM}/bin/llvm-ranlib"\n' >> /opt/abi.env \
    && . /opt/abi.env \
    && mkdir -p ${PREFIX}/{lib,include,lib/pkgconfig}

# Cross-compilation setup (per-ABI pkg-config wrapper; meson cross files)
RUN . /opt/abi.env \
    && printf '#!/bin/sh\nexport PKG_CONFIG_LIBDIR=/opt/deps/lib/pkgconfig\nexport PKG_CONFIG_PATH=\nexec pkg-config "$@"\n' \
        > /usr/local/bin/${PKGCONFIG} && chmod +x /usr/local/bin/${PKGCONFIG} \
    && ln -sf /usr/local/bin/${PKGCONFIG} ${LLVM}/bin/llvm-pkg-config

COPY build-tools/cross-android-aarch64.ini /opt/cross-android-aarch64.ini
COPY build-tools/cross-android-armv7.ini   /opt/cross-android-armv7.ini
COPY build-tools/cross-android-x86_64.ini  /opt/cross-android-x86_64.ini

# Deps (pcre2, libffi, libiconv, glib, pixman, libattr, libucontext)
RUN . /opt/abi.env && wget -q https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.44/pcre2-10.44.tar.gz && tar xf pcre2-10.44.tar.gz && cd pcre2-10.44 && ./configure --host=${CONFIG_HOST} --prefix=${PREFIX} --enable-static --disable-shared CC="${CC}" && make -j$(nproc) install
RUN . /opt/abi.env && wget -q https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz && tar xf libffi-3.4.6.tar.gz && cd libffi-3.4.6 && ./configure --host=${CONFIG_HOST} --prefix=${PREFIX} --enable-static --disable-shared CC="${CC}" && make -j$(nproc) install
# API-26 Bionic lacks iconv symbols in libc. Provide a tiny libiconv shim so
# glib can link in the cross build. It implements byte-for-byte passthrough.
RUN . /opt/abi.env && printf '#ifndef PODROID_ICONV_H\n#define PODROID_ICONV_H\n#include <stddef.h>\ntypedef void *iconv_t;\niconv_t iconv_open(const char *tocode, const char *fromcode);\nsize_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);\nint iconv_close(iconv_t cd);\n#endif\n' > ${PREFIX}/include/iconv.h \
    && printf '#include <errno.h>\n#include <stddef.h>\n#include <string.h>\n#include <iconv.h>\niconv_t iconv_open(const char *tocode, const char *fromcode) {\n    if (!tocode || !fromcode) { errno = EINVAL; return (iconv_t)-1; }\n    return (iconv_t)1;\n}\nsize_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft) {\n    (void)cd;\n    if (!inbuf || !inbytesleft || !outbuf || !outbytesleft) { errno = EINVAL; return (size_t)-1; }\n    if (!*inbuf || *inbytesleft == 0) return 0;\n    if (!*outbuf || *outbytesleft == 0) { errno = E2BIG; return (size_t)-1; }\n    size_t n = (*inbytesleft < *outbytesleft) ? *inbytesleft : *outbytesleft;\n    memcpy(*outbuf, *inbuf, n);\n    *inbuf += n;\n    *outbuf += n;\n    *inbytesleft -= n;\n    *outbytesleft -= n;\n    if (*inbytesleft != 0) { errno = E2BIG; return (size_t)-1; }\n    return 0;\n}\nint iconv_close(iconv_t cd) {\n    (void)cd;\n    return 0;\n}\n' > /tmp/iconv_shim.c \
    && ${CC} --sysroot=${LLVM}/sysroot -target ${TARGET} -I${PREFIX}/include -c /tmp/iconv_shim.c -o /tmp/iconv_shim.o \
    && ${AR} rcs ${PREFIX}/lib/libiconv.a /tmp/iconv_shim.o \
    && cp ${PREFIX}/lib/libiconv.a ${LLVM}/sysroot/usr/lib/${SYSROOT_LIBDIR}/26/libiconv.a
RUN . /opt/abi.env && wget -q https://download.gnome.org/sources/glib/2.82/glib-2.82.5.tar.xz&& tar xf glib-2.82.5.tar.xz && cd glib-2.82.5 && meson setup _build --cross-file ${MESON_CROSS} --prefix ${PREFIX} --default-library static -Dselinux=disabled -Dlibmount=disabled && ninja -C _build install
RUN . /opt/abi.env && wget -q https://cairographics.org/releases/pixman-0.44.2.tar.xz && tar xf pixman-0.44.2.tar.xz && cd pixman-0.44.2 && \
    if [ "$ABI" = arm64-v8a ]; then NEON_FLAG="-Da64-neon=disabled"; else NEON_FLAG=""; fi && \
    meson setup _build --cross-file ${MESON_CROSS} --prefix ${PREFIX} --default-library static ${NEON_FLAG} && ninja -C _build install
RUN . /opt/abi.env && wget -q https://download.savannah.gnu.org/releases/attr/attr-2.5.2.tar.gz && tar xf attr-2.5.2.tar.gz && cd attr-2.5.2 && ./configure --host=${CONFIG_HOST} --prefix=${PREFIX} --enable-static --disable-shared CC="${CC}" && make -j$(nproc) install && cp ${PREFIX}/lib/libattr.a ${LLVM}/sysroot/usr/lib/${SYSROOT_LIBDIR}/26/libattr.a
RUN . /opt/abi.env && git clone --depth=1 https://github.com/kaniini/libucontext.git /tmp/libucontext && make -C /tmp/libucontext ARCH=${UC_ARCH} CC="${CC}" EXPORT_UNPREFIXED=yes && install -Dm644 /tmp/libucontext/libucontext.a ${PREFIX}/lib/libucontext.a && install -Dm644 /tmp/libucontext/include/libucontext/libucontext.h ${PREFIX}/include/libucontext/libucontext.h && find /tmp/libucontext -name bits.h -path '*libucontext*' -exec install -Dm644 {} ${PREFIX}/include/libucontext/bits.h \; \
    && printf '#ifndef PODROID_UCONTEXT_SHIM_H\n#define PODROID_UCONTEXT_SHIM_H\n#include_next <ucontext.h>\n#include <libucontext/libucontext.h>\n#define getcontext libucontext_getcontext\n#define makecontext libucontext_makecontext\n#define setcontext libucontext_setcontext\n#define swapcontext libucontext_swapcontext\n#endif\n' > ${PREFIX}/include/ucontext.h

# libusb — required for QEMU's usb-host device. USB passthrough on Android can
# never open /dev/bus/usb itself, so QEMU receives an already-open fd over QMP
# and hands it to libusb_wrap_sys_device(); --disable-udev because Android has
# no udev and we never enumerate (every device arrives as a passed-in fd).
RUN . /opt/abi.env && wget -q https://github.com/libusb/libusb/releases/download/v1.0.27/libusb-1.0.27.tar.bz2 \
    && tar xf libusb-1.0.27.tar.bz2 && cd libusb-1.0.27 \
    && ./configure --host=${CONFIG_HOST} --prefix=${PREFIX} --enable-static --disable-shared --disable-udev CC="${CC}" \
    && make -j$(nproc) install

# QEMU Build (committed flags — no LTO, no -O3 — plus minimal Android compat patches)
RUN wget -q https://download.qemu.org/${QEMU_DIR}.tar.xz && tar xf ${QEMU_DIR}.tar.xz
RUN sed -i "s/rt = cc.find_library('rt', required: true)/rt = cc.find_library('rt', required: false)/" ${QEMU_DIR}/meson.build
RUN printf '#undef st_atime_nsec\n#undef st_mtime_nsec\n#undef st_ctime_nsec\n' | cat - ${QEMU_DIR}/fsdev/9p-marshal.h > /tmp/9p-marshal.h && mv /tmp/9p-marshal.h ${QEMU_DIR}/fsdev/9p-marshal.h
# ivshmem-{server,client} also call shm_open; stub their meson.build files since we don't ship them
RUN printf '# disabled for Android Bionic\n' > ${QEMU_DIR}/contrib/ivshmem-server/meson.build \
    && printf '# disabled for Android Bionic\n' > ${QEMU_DIR}/contrib/ivshmem-client/meson.build
# shm_open/shm_unlink are absent from the NDK API-26 stubs.
# Shim header: forward-declares them for all QEMU TUs.
# libshm.a: provides an implementation via memfd_create (works on all Android 8+ kernels).
RUN printf '#ifndef PODROID_SHM_SHIM_H\n#define PODROID_SHM_SHIM_H\nextern int shm_open(const char *, int, unsigned);\nextern int shm_unlink(const char *);\n#endif\n' \
    > /opt/shm_shim.h
RUN . /opt/abi.env && printf '#include <sys/syscall.h>\n#include <unistd.h>\n#include <errno.h>\n#ifndef SYS_memfd_create\n#define SYS_memfd_create 279\n#endif\nint shm_open(const char *n, int f, unsigned m) {\n    (void)f; (void)m;\n    while (*n == '"'"'/'"'"') n++;\n    long fd = syscall(SYS_memfd_create, n, 0);\n    if (fd < 0) { errno = (int)(-fd); return -1; }\n    return (int)fd;\n}\nint shm_unlink(const char *n) { (void)n; return 0; }\n' \
    > /tmp/shm_stub.c \
    && ${CC} --sysroot=${LLVM}/sysroot -target ${TARGET} -c /tmp/shm_stub.c -o /tmp/shm_stub.o \
    && ${AR} rcs ${PREFIX}/lib/libshm.a /tmp/shm_stub.o

# coroutine sigsetjmp shim — Bionic's sigsetjmp uses PAC instructions (paciasp /
# autiasp) to sign the saved return address. On Pixel 10 (ARMv9.2-A, Tensor G6)
# QEMU's coroutine-ucontext.c calls sigsetjmp on one glib worker thread and
# siglongjmp's back from another, and the PAC AUTH fails -> SIGILL ILL_ILLOPN.
# This shim provides drop-in replacements that just save/restore the AArch64
# callee-saved register set (x19-x30, sp, d8-d15) with no PAC, no signal mask,
# no syscalls, no stack-protector wrapping. ~22 doublewords -> fits in sigjmp_buf.
RUN printf '#ifndef PODROID_QEMU_JMP_H\n#define PODROID_QEMU_JMP_H\n#include <setjmp.h>\nextern int _qemu_setjmp(sigjmp_buf);\n__attribute__((noreturn)) extern void _qemu_longjmp(sigjmp_buf, int);\n#endif\n' > /opt/qemu_jmp.h \
    && printf '.text\n.global _qemu_setjmp\n.type _qemu_setjmp,%%function\n_qemu_setjmp:\nstp x19,x20,[x0,#0]\nstp x21,x22,[x0,#16]\nstp x23,x24,[x0,#32]\nstp x25,x26,[x0,#48]\nstp x27,x28,[x0,#64]\nstp x29,x30,[x0,#80]\nmov x9,sp\nstr x9,[x0,#96]\nstp d8,d9,[x0,#104]\nstp d10,d11,[x0,#120]\nstp d12,d13,[x0,#136]\nstp d14,d15,[x0,#152]\nmov w0,#0\nret\n.size _qemu_setjmp,.-_qemu_setjmp\n.global _qemu_longjmp\n.type _qemu_longjmp,%%function\n_qemu_longjmp:\nldp x19,x20,[x0,#0]\nldp x21,x22,[x0,#16]\nldp x23,x24,[x0,#32]\nldp x25,x26,[x0,#48]\nldp x27,x28,[x0,#64]\nldp x29,x30,[x0,#80]\nldr x9,[x0,#96]\nmov sp,x9\nldp d8,d9,[x0,#104]\nldp d10,d11,[x0,#120]\nldp d12,d13,[x0,#136]\nldp d14,d15,[x0,#152]\ncmp w1,#0\ncsinc w0,w1,wzr,ne\nbr x30\n.size _qemu_longjmp,.-_qemu_longjmp\n.section .note.GNU-stack,"",%%progbits\n' > /tmp/qemu_jmp.S

# PAC-safe sigsetjmp shim — AArch64 ONLY (ARMv9.2 PAC devices, e.g. Pixel 10).
# 32-bit ARM has no PAC, so armv7 uses libc's sigsetjmp/siglongjmp unchanged.
RUN . /opt/abi.env && if [ "$ABI" = arm64-v8a ]; then \
      ${CC} --sysroot=${LLVM}/sysroot -target ${TARGET} -c /tmp/qemu_jmp.S -o /tmp/qemu_jmp.o \
      && ${AR} rcs ${PREFIX}/lib/libqemujmp.a /tmp/qemu_jmp.o; \
    fi

# Patch coroutine-ucontext.c to call our PAC-free shim instead of libc's sigsetjmp/siglongjmp (aarch64 only).
RUN if [ "$ABI" = arm64-v8a ]; then \
      sed -i '1i#include "/opt/qemu_jmp.h"' ${QEMU_DIR}/util/coroutine-ucontext.c \
      && sed -i 's/\bsigsetjmp(\([^,]*\), *0)/_qemu_setjmp(\1)/g' ${QEMU_DIR}/util/coroutine-ucontext.c \
      && sed -i 's/\bsiglongjmp(/_qemu_longjmp(/g' ${QEMU_DIR}/util/coroutine-ucontext.c; \
    fi

# USB passthrough on Android: an unprivileged app can't scan /sys/bus/usb or open
# /dev/bus/usb, so libusb's default enumeration in libusb_init() fails with
# "failed to init libusb" and device_add usb-host never works. We only ever wrap
# a fd handed over from UsbDeviceConnection (libusb_wrap_sys_device), so set
# LIBUSB_OPTION_NO_DEVICE_DISCOVERY before libusb_init to skip enumeration.
RUN sed -i 's@^    rc = libusb_init(&ctx);@#if defined(__ANDROID__)\n    libusb_set_option(NULL, LIBUSB_OPTION_NO_DEVICE_DISCOVERY); /* unprivileged Android: wrap passed fd only, skip enumeration */\n#endif\n    rc = libusb_init(\&ctx);@' ${QEMU_DIR}/hw/usb/host-libusb.c \
    && grep -q LIBUSB_OPTION_NO_DEVICE_DISCOVERY ${QEMU_DIR}/hw/usb/host-libusb.c

# USB passthrough speed fix: on Android hosts where libusb's USBDEVFS_GET_SPEED
# ioctl fails (older/vendor kernels, SELinux), libusb_wrap_sys_device() reports
# LIBUSB_SPEED_UNKNOWN. QEMU's speed_map[] has no UNKNOWN entry, so it falls to
# speed_map[0] — and USB_SPEED_LOW == 0 — presenting EVERY wrapped device as
# low-speed. The guest kernel then rejects any device whose ep0 maxpacket isn't
# 8 ("Invalid ep0 maxpacket: 64" + endless power-cycle). Derive a consistent
# speed from the real device descriptor instead (9 = USB3 -> super, else full).
RUN sed -i 's@udev->speed = speed_map\[libusb_speed\];@udev->speed = speed_map[libusb_speed];\n    /* Podroid: libusb_wrap_sys_device() reports LIBUSB_SPEED_UNKNOWN when the\n     * host kernel USBDEVFS_GET_SPEED ioctl fails on Android; speed_map[] has\n     * no UNKNOWN entry, so it falls to speed_map[0] == USB_SPEED_LOW and every\n     * wrapped device is presented low-speed (guest rejects ep0 != 8). */\n    if (udev->speed == USB_SPEED_LOW \&\& s->ddesc.bMaxPacketSize0 != 8) {\n        udev->speed = (s->ddesc.bMaxPacketSize0 == 9) ? USB_SPEED_SUPER : USB_SPEED_FULL;\n    }@' ${QEMU_DIR}/hw/usb/host-libusb.c \
    && grep -q "USBDEVFS_GET_SPEED ioctl fails on Android" ${QEMU_DIR}/hw/usb/host-libusb.c

RUN . /opt/abi.env && cd ${QEMU_DIR} && \
    JMPLIB=""; [ "$ABI" = arm64-v8a ] && JMPLIB="${PREFIX}/lib/libqemujmp.a"; \
    CPU_FLAG=""; [ "$ABI" = armeabi-v7a ] && CPU_FLAG="--cpu=arm"; \
    [ "$ABI" = x86_64 ] && CPU_FLAG="--cpu=x86_64"; \
    ./configure --cc="${CC}" --cross-prefix="${LLVM}/bin/llvm-" --extra-cflags="-fPIC -DANDROID -include /opt/shm_shim.h -I${PREFIX}/include -I${PREFIX}/include/glib-2.0 -I${PREFIX}/lib/glib-2.0/include" --extra-ldflags="-L${PREFIX}/lib ${QEMU_ALIGN} ${EXTRA_ATOMIC} ${PREFIX}/lib/libucontext.a ${PREFIX}/lib/libshm.a ${JMPLIB}" --prefix=/opt/qemu-out --target-list=aarch64-softmmu --enable-tcg --enable-slirp --enable-virtfs --enable-libusb --enable-pie --disable-docs --disable-gtk --disable-sdl --disable-vnc --disable-vhost-user --disable-plugins --with-coroutine=ucontext ${CPU_FLAG} && make -j$(nproc) install

# Bridge
COPY podroid-bridge.c /tmp/podroid-bridge.c
RUN . /opt/abi.env && ${CC} --sysroot=${LLVM}/sysroot -target ${TARGET} -fPIE -pie ${QEMU_ALIGN} /tmp/podroid-bridge.c -o /opt/qemu-out/libpodroid-bridge.so

# Launcher (PR_SET_PDEATHSIG wrapper for QEMU — see podroid-launcher.c)
COPY podroid-launcher.c /tmp/podroid-launcher.c
RUN . /opt/abi.env && ${CC} --sysroot=${LLVM}/sysroot -target ${TARGET} -fPIE -pie ${QEMU_ALIGN} /tmp/podroid-launcher.c -o /opt/qemu-out/libpodroid-launcher.so

# Soname fix
RUN cp /opt/qemu-out/bin/qemu-system-aarch64 /opt/qemu-out/libqemu-system-aarch64.so \
    && cp /opt/qemu-out/lib/libslirp.so.0 /opt/qemu-out/libslirp.so \
    && patchelf --set-soname libslirp.so /opt/qemu-out/libslirp.so \
    && patchelf --replace-needed libslirp.so.0 libslirp.so /opt/qemu-out/libqemu-system-aarch64.so

# ==============================================================================
# SECTION 3: Final Artifacts Stage
# ==============================================================================

FROM scratch AS final
# Initramfs
COPY --from=packer /output/vmlinuz-virt /vmlinuz-virt
COPY --from=packer /output/initrd.img /initrd.img
# QEMU
COPY --from=qemu-builder /opt/qemu-out/libqemu-system-aarch64.so /libqemu-system-aarch64.so
COPY --from=qemu-builder /opt/qemu-out/libslirp.so /libslirp.so
COPY --from=qemu-builder /opt/qemu-out/libpodroid-bridge.so /libpodroid-bridge.so
COPY --from=qemu-builder /opt/qemu-out/libpodroid-launcher.so /libpodroid-launcher.so
COPY --from=qemu-builder /opt/qemu-out/share/qemu/efi-virtio.rom /qemu/efi-virtio.rom
COPY --from=qemu-builder /opt/qemu-out/share/qemu/keymaps/ /qemu/keymaps/
