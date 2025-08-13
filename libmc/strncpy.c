#include "libmc.h"

char *strncpy(char *dest, const char *src, int n) {
    int i = 0;

    // Copy characters from src to dest until null terminator or n chars
    while (i < n && src[i] != '\0') {
        dest[i] = src[i];
        i++;
    }

    // Pad with '\0' if src is shorter than n
    while (i < n) {
        dest[i] = '\0';
        i++;
    }

    return dest;
}
