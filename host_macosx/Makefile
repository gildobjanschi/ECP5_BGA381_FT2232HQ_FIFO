DEPENDENCIES := -lftd2xx -lpthread

UNAME := $(shell uname)
# Assume target is Mac OS if build host is Mac OS; any other host targets Linux
ifeq ($(UNAME), Darwin)
	DEPENDENCIES += -lobjc -framework IOKit -framework CoreFoundation
else
	DEPENDENCIES += -lrt
endif

# Embed in the executable a run-time path to libftd2xx
LINKER_OPTIONS := -Wl,-rpath /usr/local/lib

CFLAGS = -Wall -Wextra $(DEPENDENCIES) $(LINKER_OPTIONS) -L/usr/local/lib

APP = ft2232
TEST_APP = ft2232_test
LOOPBACK_APP = ft2232_loopback

all: $(APP)

test: $(TEST_APP)

loopback: $(LOOPBACK_APP)

$(APP): main.c wav_reader.c
	$(CC) wav_reader.c main.c -o $(APP) $(CFLAGS)

$(TEST_APP): main_test.c
	$(CC) main_test.c -o $(TEST_APP) $(CFLAGS)

$(LOOPBACK_APP): main_loopback.c
	$(CC) main_loopback.c -o $(LOOPBACK_APP) $(CFLAGS)

clean:
	-rm -f *.o ; rm -f $(APP); rm -f $(TEST_APP); rm -f $(LOOPBACK_APP)
