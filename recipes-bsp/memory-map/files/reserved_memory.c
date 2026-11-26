#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include <linux/io.h>
#include <linux/mm.h>
#include <linux/slab.h>
#include <linux/cdev.h>

// --- Configuration matching the DTS entry ---
// Base physical address: 0x080000000 (1 GiB)
#define DDR_PHYS_ADDR (0x800000000ULL) 
// Size: 0x100000000 (~4 GiB)
#define DDR_SIZE      (0x100000000ULL)

// Convert physical address to Page Frame Number (PFN)
// Essential divides the starting address by the page size to find the starting page file number
#define DDR_PFN_START (DDR_PHYS_ADDR >> PAGE_SHIFT)

// The device name that will appear in /dev/
#define DEVICE_NAME "reserved_memory"

// Module Metadata
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Kyle MacNeil");
MODULE_DESCRIPTION("Expose reserved DDR memory to user space via mmap.");
MODULE_VERSION("1.0");

// --- Character Device Setup ---
static dev_t ddr_dev_num;
static struct class* ddr_class = NULL;
static struct device* ddr_dev = NULL;
static struct cdev ddr_cdev;

/**
 * ddr_mmap: Maps the physical memory region into the user-space virtual address.
 * @filp: Pointer to the file structure.
 * @vma: Pointer to the Virtual Memory Area structure.
 * * This function is the core of the module, allowing user-space direct access.
 */
static int ddr_mmap(struct file *filp, struct vm_area_struct *vma)
{
	unsigned long pfn_start = DDR_PFN_START;
	unsigned long size = vma->vm_end - vma->vm_start;
	unsigned long offset = vma->vm_pgoff << PAGE_SHIFT;

	// 1. Validate the requested mapping size and offset
	if (offset >= DDR_SIZE) {
		pr_err("DDR_MAP: Invalid offset 0x%lx\n", offset);
		return -EINVAL;
	}

	if ((offset + size) > DDR_SIZE) {
		pr_err("DDR_MAP: Requested size (0x%lx) + offset (0x%lx) exceeds DDR region size (0x%llx)\n", size, offset, DDR_SIZE);
		return -EINVAL;
	}

	// Adjust PFN start based on the offset requested by the user
	pfn_start += vma->vm_pgoff;

	// 2. Set VM Flags
	// Mark the memory as non-cacheable (essential for 'no-map' regions)
	vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);
	
	// Ensure memory cannot be swapped out
	vm_flags_set(vma, VM_IO | VM_DONTDUMP | VM_DONTEXPAND);

	// 3. Map the physical memory to the user's virtual address space
	// remap_pfn_range(vma, virt_addr, pfn, size, prot)
	if (remap_pfn_range(vma, vma->vm_start, pfn_start, size, vma->vm_page_prot)) {
		pr_err("DDR_MAP: Failed to remap physical memory range.\n");
		return -EAGAIN;
	}

	pr_info("DDR_MAP: Successfully mapped 0x%lx bytes (PFN 0x%lx) to user virtual address 0x%lx\n", 
			size, pfn_start, vma->vm_start);

	return 0;
}

/**
 * ddr_open: Standard char device open operation.
 */
static int ddr_open(struct inode *inode, struct file *filp)
{
	pr_info("DDR_MAP: Device opened.\n");
	return 0;
}

/**
 * ddr_release: Standard char device release operation.
 */
static int ddr_release(struct inode *inode, struct file *filp)
{
	pr_info("DDR_MAP: Device closed.\n");
	return 0;
}

// File operations structure
static const struct file_operations ddr_fops = {
	.owner = THIS_MODULE,
	.open = ddr_open,
	.release = ddr_release,
	.mmap = ddr_mmap,
};

/**
 * ddr_map_init: Module initialization function.
 */
static int __init ddr_map_init(void)
{
	int ret;

	pr_info("DDR_MAP: Initializing module to map reserved memory at 0x%llx (Size: 0x%llx)\n", 
			DDR_PHYS_ADDR, DDR_SIZE);

	// 1. Dynamically allocate a major and minor number for the device
	ret = alloc_chrdev_region(&ddr_dev_num, 0, 1, DEVICE_NAME);
	if (ret < 0) {
		pr_err("DDR_MAP: Failed to allocate char dev region. Ret: %d\n", ret);
		return ret;
	}

	// 2. Create a unique device class for "ddr_uncached_mem" (needed for auto-creating /dev entry)
	ddr_class = class_create(DEVICE_NAME);
	if (IS_ERR(ddr_class)) {
		unregister_chrdev_region(ddr_dev_num, 1);
		pr_err("DDR_MAP: Failed to create device class.\n");
		return PTR_ERR(ddr_class);
	}

	// 3. Create the device file in /dev
	ddr_dev = device_create(ddr_class, NULL, ddr_dev_num, NULL, DEVICE_NAME);
	if (IS_ERR(ddr_dev)) {
		class_destroy(ddr_class);
		unregister_chrdev_region(ddr_dev_num, 1);
		pr_err("DDR_MAP: Failed to create device.\n");
		return PTR_ERR(ddr_dev);
	}

	// 4. Connect the file operations to the device
	cdev_init(&ddr_cdev, &ddr_fops);
	ret = cdev_add(&ddr_cdev, ddr_dev_num, 1);
	if (ret < 0) {
		device_destroy(ddr_class, ddr_dev_num);
		class_destroy(ddr_class);
		unregister_chrdev_region(ddr_dev_num, 1);
		pr_err("DDR_MAP: Failed to add cdev.\n");
		return ret;
	}
	
	pr_info("DDR_MAP: Device /dev/%s created successfully with Major %d.\n", DEVICE_NAME, MAJOR(ddr_dev_num));

	return 0;
}

/**
 * ddr_map_exit: Module cleanup function.
 */
static void __exit ddr_map_exit(void)
{
	// 1. Remove the character device
	cdev_del(&ddr_cdev); 

	// 2. Destroy the device file
	device_destroy(ddr_class, ddr_dev_num);
	
	// 3. Destroy the device class
	class_destroy(ddr_class);
	
	// 4. Unregister the major/minor number
	unregister_chrdev_region(ddr_dev_num, 1);
	
	pr_info("DDR_MAP: Module unloaded and device /dev/%s cleaned up.\n", DEVICE_NAME);
}

// Module entry and exit points
module_init(ddr_map_init);
module_exit(ddr_map_exit);
