#!/usr/bin/env bash
set -euo pipefail

KERNEL_DIR="${1:?need path to kernel source tree}"
cd "${KERNEL_DIR}"

MARKER='AVD_SPOOF_INJECTED'

# 1. /proc/modules filter — hide emulator-fingerprint module names
# In android13-5.15, module procfs is in kernel/module.c (single file).
# In android15-6.6, it's split into kernel/module/procfs.c.
if [ -f kernel/module/procfs.c ]; then
    f=kernel/module/procfs.c
else
    f=kernel/module.c
fi
if grep -q "${MARKER}" "$f"; then
    echo "  - ${f}: already injected"
else
    echo "  - ${f}: injecting /proc/modules blocklist"
    python3 - "$f" <<'PY'
import sys, re
path = sys.argv[1]
src = open(path).read()

block = r'''
/* AVD_SPOOF_INJECTED: hide emulator-fingerprint modules from /proc/modules */
static const char * const avd_hidden_module_names[] = {
	"goldfish_pipe", "goldfish_sync", "goldfish_address_space",
	"goldfish_battery", "goldfish_audio", "goldfish_camera",
	"goldfish_fb", "goldfish_tty", "goldfish_nand",
	"virt_wifi", "mac80211_hwsim",
	"virtio_gpu", "virtio_dma_buf", "virtio_snd", "virtio_input",
	"virtio_net", "virtio_blk", "virtio_pmem", "virtio_console",
	"virtio_balloon", "virtio_rng",
	NULL,
};
static bool avd_module_hidden(const char *name)
{
	int i;
	for (i = 0; avd_hidden_module_names[i]; i++)
		if (!strcmp(name, avd_hidden_module_names[i]))
			return true;
	return false;
}
'''

m = re.search(r'^static int m_show\(struct seq_file \*m, void \*p\)\s*\{', src, re.M)
assert m, "m_show not found in " + path
src = src[:m.start()] + block + '\n' + src[m.start():]

m2 = re.search(
    r'(static int m_show\(struct seq_file \*m, void \*p\)\s*\{\s*\n'
    r'(?:\s+[^\n]*;\s*\n)+)',
    src
)
assert m2, "couldn't locate body of m_show"
inject = '\n\tif (avd_module_hidden(mod->name))\n\t\treturn 0;\n'
src = src[:m2.end()] + inject + src[m2.end():]

open(path, 'w').write(src)
PY
fi

# 2. /proc/cpuinfo — x86_64: replace "Android virtual processor" model name
# SUSFS open_redirect + mount --bind handle the full fake file at runtime,
# but some apps read cpuinfo via sysfs or other paths. Patch the model name
# in the kernel as a defense-in-depth.
f=arch/x86/kernel/cpu/proc.c
if grep -q "${MARKER}" "$f"; then
    echo "  - ${f}: already injected"
else
    echo "  - ${f}: injecting model name spoof"
    python3 - "$f" <<'PY'
import sys, re
path = sys.argv[1]
src = open(path).read()

marker_comment = '/* AVD_SPOOF_INJECTED: replace emulator model name */\n'
# Replace the model name seq_printf to use a neutral string
src = re.sub(
    r'seq_printf\(m, "model name\\t: %s\\n", c->x86_model_id\);',
    marker_comment + '\tseq_printf(m, "model name\\t: Intel(R) Core(TM) i7-12700K CPU @ 3.60GHz\\n");',
    src
)

open(path, 'w').write(src)
PY
fi

echo "==> kernel customization complete"