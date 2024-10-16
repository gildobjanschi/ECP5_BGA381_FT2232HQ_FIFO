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
APP_FILE = ft2232_file

all: $(APP)
file: $(APP_FILE)

$(APP): main.c wav_reader.c
	$(CC) wav_reader.c main.c -o $(APP) $(CFLAGS)
$(APP_FILE): main_output_file.c wav_reader.c
	$(CC) wav_reader.c main_output_file.c -o $(APP_FILE) $(CFLAGS)

clean:
	-rm -f *.o ; rm -f $(APP); rm -f $(APP_FILE);
