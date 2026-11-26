#include <linux/module.h>
#include <linux/init.h>

#include <linux/gpio.h>
#include <linux/interrupt.h>

#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/signal.h>

#define GPIOINT_GPIOLINE 3  //GPIO1_IO3   32(1-1)+3 = 3
#define XBARINT_GPIOLINE 7  //GPIO1_IO7     32(1-1)+7 = 7

#define HUB_EXECNAME "Hub-UserApp"
#define USERSIGNAL 34 //This is the value of SIGRTMIN in the user space

/* Meta Information */
MODULE_LICENSE("GPL");
MODULE_AUTHOR("J-Squared Technologies/Kyle MacNeil");
MODULE_DESCRIPTION("  Hub interrupt module");

/* variable contains pin number of interrupt controller for the GPIO and Xbar interrupts, respectively */
unsigned int gpio_irq;
unsigned int xbar_irq;

pid_t pid = -1;

static void SendSignal(pid_t pid);
static pid_t GetPid(void);

/* Ther interrupt service routines (ISRs) called when an interrupt is triggered */
static irq_handler_t gpioint_irq_handler(unsigned int irq, void *dev_id) 
{
    printk("GPIO interrupt was triggered and ISR was called \n");

    pid = GetPid();

    SendSignal(pid);

    return (irq_handler_t) IRQ_HANDLED;
}

static irq_handler_t xbarint_irq_handler(unsigned int irq, void *dev_id) 
{
    printk("XBAR interrupt was triggered and ISR was called \n");

    pid = GetPid();

    SendSignal(pid);

    return (irq_handler_t) IRQ_HANDLED;
}

static void GpioIrqMapping(void)
{
    /* Setup the gpio */
    if(gpio_request((unsigned int)GPIOINT_GPIOLINE, "GPIOINT_GPIO"))
    {
        printk(KERN_ERR "Error in function %s : Can not allocate GPIO INT, GPIO5_IO15", __func__);
        
    }

    if(gpio_request((unsigned int)XBARINT_GPIOLINE, "XBARINT_GPIO"))
    {
        printk(KERN_ERR "Error in function %s : Can not allocate XBAR INT, GPIO1_IO07", __func__);
        
    }

    /* Set the direction of the gpio */
    if(gpio_direction_input((unsigned int)GPIOINT_GPIOLINE))
    {
        printk(KERN_ERR "Error in function %s : Can not set direction of GPIO INT, GPIO5_IO15", __func__);
        
    };

    if(gpio_direction_input((unsigned int)XBARINT_GPIOLINE))
    {
        printk(KERN_ERR "Error in function %s : Can not set direction of XBAR INT, GPIO1_IO07", __func__);
        
    };
    
    /* Map the GPIO lines to IRQ pins */
    gpio_irq = gpio_to_irq((unsigned int)GPIOINT_GPIOLINE);
    xbar_irq = gpio_to_irq((unsigned int)XBARINT_GPIOLINE);

    /* Request the IRQ and map the IRQ to its interrupt service routine (ISR) */
    if(request_irq(gpio_irq, (irq_handler_t) gpioint_irq_handler, IRQF_TRIGGER_FALLING,"gpio_irq", NULL) != 0)
    {
        printk(KERN_ERR "Error in function %s :\nGPIO can not request interrupt nr.: %d\n", __func__, gpio_irq);
        gpio_free(GPIOINT_GPIOLINE);
        
    }

    if(request_irq(xbar_irq, (irq_handler_t) xbarint_irq_handler, IRQF_TRIGGER_FALLING,"xbar_irq", NULL) != 0)
    {
        printk(KERN_ERR "Error in function %s :\nXbar can not request interrupt nr.: %d\n", __func__, xbar_irq);
        gpio_free(GPIOINT_GPIOLINE);
        
    }

    printk(KERN_INFO "GPIO interrupt line is mapped to IRQ nr.: %d\n", gpio_irq);
    printk(KERN_INFO "Xbar interrupt line is mapped to IRQ nr.: %d\n", xbar_irq);
}

static pid_t GetPid(void)
{
    struct task_struct *task;
    const char *target_process =  HUB_EXECNAME;

    // Iterate over each process in the system
    for_each_process(task) {
        // Compare the process name
        if (strcmp(task->comm, target_process) == 0) {
            pid = task->pid;
            printk(KERN_INFO "Found process %s with PID: %d\n", target_process, pid);
            break;
        }
    }

    if (pid == -1) {
        printk(KERN_INFO "Process %s not found\n", target_process);
    }   

    return pid; 
}

static void SendSignal(pid_t pid)
{   
    struct pid *pid_struct;
    struct task_struct *task;
    struct kernel_siginfo info;

    printk(KERN_INFO "About to send an interrupt signal to process with following PID, %d", pid);

    pid_struct = find_get_pid(pid);
    task = pid_task(pid_struct, PIDTYPE_PID);
    
    if (!task) {
        printk(KERN_INFO "Cannot find the user space process associated with PID %d\n", pid);
    }

    memset(&info, 0, sizeof(struct kernel_siginfo));
    info.si_signo = USERSIGNAL ;
    info.si_code = SI_QUEUE;

    if (send_sig_info(USERSIGNAL, &info, task) < 0) {
        printk(KERN_ERR "Error in function %s : Failed to send POSIX Real-Time Signal", __func__);
    }
    else
    {
        printk(KERN_INFO " Successfully sent POSIX Real-Time Signal");
    }
    
}

/* This function is called, when the module is loaded into the kernel */
static int __init ModuleInit(void) {

    printk("  Hub interrupt module is loading...\n");

    GpioIrqMapping();

    printk("  Hub interrupt module is DONE \n");
    return 0;
}

static void __exit ModuleExit(void) {
    printk("Unloading module...\n");

    free_irq(gpio_irq, NULL);
    gpio_free(GPIOINT_GPIOLINE);

    free_irq(xbar_irq, NULL);
    gpio_free(XBARINT_GPIOLINE);

    printk("  Hub interrupt module removed\n");
}

module_init(ModuleInit);
module_exit(ModuleExit);
