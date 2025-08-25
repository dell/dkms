#include <linux/module.h>
#include <linux/kernel.h>

static int __init dkms_per_module_kernel_version_test_old_init(void)
{
    printk(KERN_INFO "dkms_per_module_kernel_version_test_old: module loaded\n");
    return 0;
}

static void __exit dkms_per_module_kernel_version_test_old_exit(void)
{
    printk(KERN_INFO "dkms_per_module_kernel_version_test_old: module unloaded\n");
}

module_init(dkms_per_module_kernel_version_test_old_init);
module_exit(dkms_per_module_kernel_version_test_old_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("DKMS per-module kernel version test - old kernel module");
MODULE_VERSION("1.0");
