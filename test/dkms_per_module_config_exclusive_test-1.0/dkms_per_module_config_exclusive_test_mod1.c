#include <linux/module.h>
#include <linux/kernel.h>

static int __init dkms_per_module_config_exclusive_test_mod1_init(void)
{
    printk(KERN_INFO "dkms_per_module_config_exclusive_test_mod1: module loaded\n");
    return 0;
}

static void __exit dkms_per_module_config_exclusive_test_mod1_exit(void)
{
    printk(KERN_INFO "dkms_per_module_config_exclusive_test_mod1: module unloaded\n");
}

module_init(dkms_per_module_config_exclusive_test_mod1_init);
module_exit(dkms_per_module_config_exclusive_test_mod1_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("DKMS per-module config exclusive test module 1");
MODULE_VERSION("1.0");
