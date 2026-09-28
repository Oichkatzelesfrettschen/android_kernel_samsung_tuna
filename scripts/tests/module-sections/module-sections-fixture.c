#include <linux/errno.h>
#include <linux/init.h>
#include <linux/module.h>

static int fixture_value;
module_param(fixture_value, int, 0444);

static int __init module_sections_fixture_init(void)
{
	return fixture_value < 0 ? -EINVAL : 0;
}

static void __exit module_sections_fixture_exit(void)
{
}

module_init(module_sections_fixture_init);
module_exit(module_sections_fixture_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("ARM module section validation fixture");
