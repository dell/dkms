#include <linux/module.h>
#include <linux/kernel.h>

static int __init dkms_per_module_mixed_test_never_init(void)
{
    printk(KERN_INFO "dkms_per_module_mixed_test_never: module loaded\n");
    return 0;
}

static void __exit dkms_per_module_mixed_test_never_exit(void)
{
    printk(KERN_INFO "dkms_per_module_mixed_test_never: module unloaded\n");
}

module_init(dkms_per_module_mixed_test_never_init);
module_exit(dkms_per_module_mixed_test_never_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("DKMS per-module mixed test - never builds");
MODULE_VERSION("1.0");
