#include <linux/module.h>
#include <linux/kernel.h>

static int __init dkms_per_module_kernel_version_test_new_init(void)
{
    printk(KERN_INFO "dkms_per_module_kernel_version_test_new: module loaded\n");
    return 0;
}

static void __exit dkms_per_module_kernel_version_test_new_exit(void)
{
    printk(KERN_INFO "dkms_per_module_kernel_version_test_new: module unloaded\n");
}

module_init(dkms_per_module_kernel_version_test_new_init);
module_exit(dkms_per_module_kernel_version_test_new_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("DKMS per-module kernel version test - new kernel module");
MODULE_VERSION("1.0");
