#include "libmc/libmc.h"

/*#define MEM_SIZE (48 * 1024)
#define STRIDE   64

char buffer[MEM_SIZE];

int main() {
    
    native_t i, sum = 0;

    // Fill buffer with a pattern
    memset(buffer, 0xAA, MEM_SIZE);

    puts("Buffer filled with 0xAA.\n");

    // Sequential access: sum all bytes
    for (i = 0; i < MEM_SIZE; i++) {
        sum += buffer[i];
    }
    printf("Sequential sum: %d\n", sum);

    // Strided access: touch every STRIDE-th byte
    sum = 0;
    for (i = 0; i < MEM_SIZE; i += STRIDE) {
        buffer[i] = (char)(i & 0xFF);
        sum += buffer[i];
    }
    printf("Strided sum: %d\n", sum);

    // Print a few values using itoa and printf
    for (i = 0; i < 5; i++) {
        char numstr[16];
        itoa((snative_t)buffer[i * STRIDE], numstr);
        printf("buffer[%d * %d] = %s\n", (int)i, STRIDE, numstr);
    }

    puts("Cache test complete.\n");
    
}*/

int main() {
    printf("Hello there %d\n", atoi("-55"));
}