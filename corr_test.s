#include "libmc.h"
#include <stdio.h>
#include <string.h>

#define MAX_WORDS 256
#define MAX_WORD_LEN 16
#define TEXT_SIZE 1024

volatile char text[TEXT_SIZE] = 
    "this is a test this is only a test this test is not a drill test test test";

char words[MAX_WORDS][MAX_WORD_LEN];
int counts[MAX_WORDS];
int total_words = 0;

int is_separator(char c) {
    return c == ' ' || c == '\n' || c == '\t' || c == '.' || c == ',';
}

int find_word(const char* word) {
    for (int i = 0; i < total_words; i++) {
        if (strcmp(words[i], word) == 0) {
            return i;
        }
    }
    return -1;
}

void add_word(const char* word) {
    int idx = find_word(word);
    if (idx >= 0) {
        counts[idx]++;
    } else if (total_words < MAX_WORDS) {
        strncpy(words[total_words], word, MAX_WORD_LEN - 1);
        words[total_words][MAX_WORD_LEN - 1] = '\0';
        counts[total_words] = 1;
        total_words++;
    }
}

void tokenize_and_count() {
    char current[MAX_WORD_LEN];
    int curr_len = 0;

    for (int i = 0; i < TEXT_SIZE; i++) {
        char c = text[i];
        if (c == '\0') break;

        if (is_separator(c)) {
            if (curr_len > 0) {
                current[curr_len] = '\0';
                add_word(current);
                curr_len = 0;
            }
        } else if (curr_len < MAX_WORD_LEN - 1) {
            current[curr_len++] = c;
        }
    }

    if (curr_len > 0) {
        current[curr_len] = '\0';
        add_word(current);
    }
}

void print_results() {
    printf("Word Frequencies:\n");
    for (int i = 0; i < total_words; i++) {
        printf("%s: %d\n", words[i], counts[i]);
    }
}

int main() {
    tokenize_and_count();
    print_results();
    return 0;
}
