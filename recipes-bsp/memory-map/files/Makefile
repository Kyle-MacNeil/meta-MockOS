obj-m := reserved_memory.o 

# Standard Yocto variable name for the kernel directory
# The ?= allows Yocto to pass the correct path into the Makefile
KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) modules

modules_install:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) modules_install

clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) clean

.PHONY: all clean modules_install