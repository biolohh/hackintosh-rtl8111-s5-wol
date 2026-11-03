/*
 * wolpeek: sends a WoLDiag command to the locally patched RealtekRTL8111.kext
 * and writes the result to stdout (raw bytes; "nic" prints text).
 * Build: clang -O2 -framework IOKit -framework CoreFoundation -o ./wolpeek ./wolpeek.c
 * Use:   sudo ./wolpeek "phys 0xcaac8014 36" > rsdp.bin   (commands: see RealtekRTL8111.cpp)
 */
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: wolpeek \"phys|mmio|io8|io16|io32 <addr> <len>\" | nic\n");
        return 2;
    }
    /* The driver object is not registered, so walk the service plane instead of matching. */
    io_iterator_t it;
    io_service_t s = 0, o;
    if (IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, kIORegistryIterateRecursively, &it) == KERN_SUCCESS) {
        while (!s && (o = IOIteratorNext(it))) {
            if (IOObjectConformsTo(o, "RTL8111"))
                s = o;
            else
                IOObjectRelease(o);
        }
        IOObjectRelease(it);
    }
    if (!s) {
        fprintf(stderr, "RTL8111 not found\n");
        return 1;
    }
    CFStringRef cmd = CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8);
    kern_return_t kr = IORegistryEntrySetCFProperty(s, CFSTR("WoLDiag"), cmd);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "WoLDiag failed: 0x%x\n", kr);
        return 1;
    }
    CFStringRef key = CFSTR("WoLDiag-out");
    if (!strcmp(argv[1], "nic"))
        key = CFSTR("WoLDiag-nic");
    else if (argv[1][0] == 'w' || !strncmp(argv[1], "s5run", 5) || !strncmp(argv[1], "rsio", 4))
        key = CFSTR("WoLDiag-outcmd");
    CFTypeRef v = IORegistryEntryCreateCFProperty(s, key, NULL, 0);
    if (v && CFGetTypeID(v) == CFDataGetTypeID()) {
        fwrite(CFDataGetBytePtr(v), 1, CFDataGetLength(v), stdout);
    } else if (v && CFGetTypeID(v) == CFStringGetTypeID()) {
        char b[1024];
        CFStringGetCString(v, b, sizeof(b), kCFStringEncodingUTF8);
        puts(b);
    } else {
        fprintf(stderr, "no result\n");
        return 1;
    }
    return 0;
}
