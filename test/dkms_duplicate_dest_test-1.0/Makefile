obj-m += dkms_duplicate1_dest_test.o
obj-m += dkms_duplicate2_dest_test.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
