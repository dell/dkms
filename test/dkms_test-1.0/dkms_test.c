#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

#define  DKMS_TEST_VER "1.0"

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("A Simple dkms test module");

static int __init dkms_test_init(void)
{
    printk(KERN_INFO "DKMS Test Module -%s Loaded\n",DKMS_TEST_VER);
    return 0;
}

static void __exit dkms_test_cleanup(void)
{
    printk(KERN_INFO "Cleaning up after dkms test module.\n");
}

module_init(dkms_test_init);
module_exit(dkms_test_cleanup);
MODULE_VERSION(DKMS_TEST_VER);

void dkms_test_exported_function(void)
{
    printk(KERN_INFO "Function exported by the dkms test module.\n");
}

EXPORT_SYMBOL_GPL(dkms_test_exported_function);
