# APIOAK Router Engine Makefile

UNAME := $(shell uname)

CC = gcc
CFLAGS = -O2 -Wall -Wextra -fPIC -std=c99

# Include paths
INCLUDES = -I. -I../rax -I../klib

# Source files
SRCS = apioak_router.c ../rax/rax.c
OBJS = $(SRCS:.c=.o)

# Output library name
ifeq ($(UNAME), Darwin)
    TARGET = libapioak_router.dylib
    LDFLAGS = -dynamiclib -undefined dynamic_lookup
else
    TARGET = libapioak_router.so
    LDFLAGS = -shared
endif

# Default target
all: $(TARGET)
	@rm -f $(OBJS)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

# Install to system
install: $(TARGET)
ifeq ($(UNAME), Darwin)
	install -m 755 $(TARGET) /usr/local/lib/
else
	install -m 755 $(TARGET) /usr/local/lib/
	ldconfig
endif

# Install for development (copy to lua_modules)
dev: $(TARGET)
	@mkdir -p ../../lua_modules/lib
	cp $(TARGET) ../../lua_modules/lib/

clean:
	rm -f $(OBJS) $(TARGET)
	rm -f ../rax/*.o

.PHONY: all install dev clean
