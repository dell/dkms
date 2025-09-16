#include <linux/module.h>
#include <linux/kernel.h>

static int __init dkms_per_module_config_test_mod3_init(void)
{
    printk(KERN_INFO "dkms_per_module_config_test_mod3: module loaded\n");
    return 0;
}

static void __exit dkms_per_module_config_test_mod3_exit(void)
{
    printk(KERN_INFO "dkms_per_module_config_test_mod3: module unloaded\n");
}

module_init(dkms_per_module_config_test_mod3_init);
module_exit(dkms_per_module_config_test_mod3_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("DKMS per-module config test module 3");
MODULE_VERSION("1.0");
