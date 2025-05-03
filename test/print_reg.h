#ifndef OUTPUT_LOGGER_H
#define OUTPUT_LOGGER_H

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif
// Define enums
typedef enum {
    ENTRY_EMPTY,
    ENTRY_DISPATCHED
} RSEntryState;

typedef enum {
    FU_NOP,
    FU_ALU,
    FU_MUL,
    FU_LOAD,
    FU_STORE,
    FU_BR,
    FU_HALT
} FuType;

// Global file pointers
extern FILE* rob_reg;
extern FILE* rs_reg;
extern FILE* fl_reg;
extern FILE* mt_reg;
extern FILE* bu_reg;
extern FILE* reg;
void print_cycle(int clock_count);
// Function to convert an integer to a binary string
void int_to_binary(int num, char *binary_str, int bit_size);

// Functions to manage files
void open_output_file(char* pred_file, char* pf_file, char* rob_file, char* rs_file, char* fl_file, char* mt_file, char* bu_file);
void close_output_file();

void print_pred_entry(int bhr);

void print_pf_header();
void print_pf_entry(int i, int state, int transacTag, int addr, long long data);

// Reservation Station logging
void print_rs_header();
void print_rs_entry(int i, int state, int fuType, int src1, int src1_ready, int src2, int src2_ready, int dst, int bmask, int bindex, int store_pos);

// Reorder Buffer logging
void print_rob_header();
void print_rob_entry(int i, int rd, int t_new, int t_old, int NPC, int halt, int illegal, int valid, int complete, int head, int tail);

// Free List logging
void print_free_list_header();
void print_free_list_entry(int i, int available);

// Map Table logging
void print_map_table_header();
void print_map_table_entry(int i, int pr,int ready);

// Branch Unit logging
void print_branch_stack_header();
void print_branch_stack_entry(int i, int bmask, int valid, int bidx);
void print_reg_header();
void print_reg_entry(int i, int data);
void print_issue_reg_header();
void print_issue_reg_entry(int i, int data);
void print_cdb_header();
void print_cdb_entry(int i, int data);

#ifdef __cplusplus
}
#endif

#endif // OUTPUT_LOGGER_H
