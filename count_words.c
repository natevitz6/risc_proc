#include "libmc.h"

#define MAX_WORDS 16
#define MAX_WORD_LEN 8
#define TEXT_SIZE 64

volatile char text[TEXT_SIZE] = 
    "this is a test this is only a test this test test test test";

char* words[MAX_WORDS];
int total_words = 0;

int is_separator(char c) {
    return c == ' ' || c == '\n' || c == '\t' || c == '.' || c == ',';
}

int find_word(char* word) {
    for (int i = 0; i < total_words; i++) {
        if (words[i] == word) {  // compare pointer only
            return i;
        }
    }
    return -1;
}

void tokenize() {
    int i = 0;
    while (i < TEXT_SIZE && text[i] != '\0') {
        // skip separators
        while (i < TEXT_SIZE && is_separator(text[i])) i++;
        if (i >= TEXT_SIZE || text[i] == '\0') break;

        char* start = (char*)&text[i];
        int len = 0;
        while (i < TEXT_SIZE && !is_separator(text[i]) && len < MAX_WORD_LEN) {
            i++;
            len++;
        }

        if (total_words < MAX_WORDS) {
            if (find_word(start) == -1) {
                words[total_words++] = start;
            }
        }

        // skip remaining chars of word if longer than MAX_WORD_LEN
        while (i < TEXT_SIZE && !is_separator(text[i])) i++;
    }
}

void print_results() {
    printf("Unique tokens found: %d\n", total_words);
    for (int i = 0; i < total_words; i++) {
        printf("%s\n", words[i]);
    }
}

int main() {
    tokenize();
    print_results();
    return 0;
}