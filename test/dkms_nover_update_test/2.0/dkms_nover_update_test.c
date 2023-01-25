#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("A Simple dkms test module with no version!");

static int __init dkms_test_init(void)
{
    printk(KERN_INFO "DKMS Test Module - Loaded\n");
    return 0;
}

static void __exit dkms_test_cleanup(void)
{
    printk(KERN_INFO "Cleaning up after dkms test module.\n");
}

module_init(dkms_test_init);
module_exit(dkms_test_cleanup);
