#include "print_reg.h"

// Global file pointers
FILE* pred_reg = NULL;
FILE* pf_reg = NULL;
FILE* rob_reg = NULL;
FILE* rs_reg = NULL;
FILE* fl_reg = NULL;
FILE* mt_reg = NULL;
FILE* bu_reg = NULL;

void int_to_binary(int num, char* binary_str, int bit_size) {
    binary_str[bit_size] = '\0'; // Null-terminate the string
    for (int i = bit_size - 1; i >= 0; i--) {
        binary_str[i] = (num & 1) ? '1' : '0';
        num >>= 1;
    }
}

void open_output_file(char* pred_file, char* pf_file, char* rob_file, char* rs_file, char* fl_file, char* mt_file, char* bu_file) {
	pred_reg = fopen(pred_file, "w");
    pf_reg = fopen(pf_file, "w");
    rob_reg = fopen(rob_file, "w");
    rs_reg = fopen(rs_file, "w");
    fl_reg = fopen(fl_file, "w");
    mt_reg = fopen(mt_file, "w");
    bu_reg = fopen(bu_file, "w");
}

void close_output_file() {
	if (pred_reg) { fclose(pred_reg); pred_reg = NULL; }
	if (pf_reg) { fclose(pf_reg); pf_reg = NULL; }
    if (rob_reg) { fclose(rob_reg); rob_reg = NULL; }
    if (rs_reg) { fclose(rs_reg); rs_reg = NULL; }
    if (fl_reg) { fclose(fl_reg); fl_reg = NULL; }
    if (mt_reg) { fclose(mt_reg); mt_reg = NULL; }
    if (bu_reg) { fclose(bu_reg); bu_reg = NULL; }
}

void print_cycle(int clock_count)
{
	fprintf(pred_reg, "%5d\n", clock_count);
    fprintf(pf_reg, "%5d\n", clock_count);
    fprintf(rob_reg, "%5d\n", clock_count);
    fprintf(rs_reg, "%5d\n", clock_count);
    fprintf(fl_reg, "%5d\n", clock_count);
    fprintf(mt_reg, "%5d\n", clock_count);
    fprintf(bu_reg, "%5d\n", clock_count);
}

/*
enum ePrefetchState {
    empty,
    wantRequest,
    sentRequest,
    hasData,
    hit,
};

struct PrefetchEntry {
    ePrefetchState state{ empty };
    MemTag transacTag{};
    std::bitset<32> addr{};
    std::bitset<64> data{};
};
*/

void print_pred_entry(int bhr)
{
	fprintf(pred_reg, "%-12d\n", bhr);
}

void print_pf_header() {
    fprintf(pf_reg, "| %-5s | %-12s | %-6s | %-8s | %-16s |\n",
        "IDX", "State", "Tag", "Addr", "Data");
}
void print_pf_entry(int i, int state, int transacTag, int addr, long long data) {
    const char* state_str;
    switch (state) {
        case 0: state_str = "empty"; break;
        case 1: state_str = "wantRequest"; break;
        case 2: state_str = "sentRequest"; break;
        case 3: state_str = "hasData"; break;
        case 4: state_str = "hit"; break;
        default: state_str = "unknown"; break;
    }
    fprintf(pf_reg, "| %-5d | %-12s | %-6d | %-8x | %-16llx |\n", i, state_str, transacTag, addr, data);
}

// Reservation Station
void print_rs_header() {
    fprintf(rs_reg, "| %-3s | %-10s | %-6s | %-6s | %-5s | %-6s | %-5s | %-3s | %-6s | %-6s | %-6s |\n",
        "IDX", "State", "FuType", "Src1", "Rdy1", "Src2", "Rdy2", "Dst", "bmask", "bindex", "stpos");
}
void print_rs_entry(int i, int state, int fuType, int src1, int src1_ready, int src2, int src2_ready, int dst, int bmask, int bindex, int store_pos) {
    const char* state_str = (state == ENTRY_DISPATCHED) ? "DISPATCHED" : "EMPTY";
    const char* fuType_str;

    switch (fuType) {
    case FU_ALU:  fuType_str = "ALU"; break;
    case FU_MUL:  fuType_str = "MUL"; break;
    case FU_LOAD: fuType_str = "LOAD"; break;
    case FU_STORE:fuType_str = "STORE"; break;
    case FU_BR:   fuType_str = "BR"; break;
    case FU_HALT: fuType_str = "HALT"; break;
    default:      fuType_str = "NOP"; break;
    }

    fprintf(rs_reg, "| %-3d | %-10s | %-6s | %-6d | %-5d | %-6d | %-5d | %-3d | %-5d | %-5d | %-3d |\n",
        i, state_str, fuType_str, src1, src1_ready, src2, src2_ready, dst, bmask, bindex, store_pos);
}

// ROB
void print_rob_header() {
    fprintf(rob_reg, "| %-3s | %-3s | %-5s | %-5s | %-6s | %-5s | %-7s | %-5s | %-8s | %-5s |\n",
        "IDX", "rd", "tNew", "tOld", "NPC", "Halt", "Illegal", "Valid", "Complete", "HT");
}

void print_rob_entry(int i, int rd, int t_new, int t_old, int NPC, int halt, int illegal, int valid, int complete, int head, int tail) {
    fprintf(rob_reg, "| %-3d | %-3d | %-5d | %-5d | %-6d | %-5d | %-7d | %-5d | %-8d | %-5s |\n",
        i, rd, t_new, t_old, NPC, halt, illegal, valid, complete,
        (
            (i == head && i == tail) ? "ht" : (
                i == head) ? "h" : (i == tail) ? "t" : ""
            )
    );
}

// Free List
void print_free_list_header() {
    fprintf(fl_reg, "| %-3s | %-9s |\n", "IDX", "Available");
}

void print_free_list_entry(int i, int available) {
    fprintf(fl_reg, "| %-3d | %-9d |\n", i, available);
}

// Map Table
void print_map_table_header() {
    fprintf(mt_reg, "| %-5s | %-10s | %-5s |\n", "IDX", "PhysReg", "Ready");
}

void print_map_table_entry(int i, int pr, int ready) {
    fprintf(mt_reg, "| %-5d | %-10d | %-5d |\n", i, pr, ready);
}

// Branch Unit
void print_branch_stack_header() {
    fprintf(bu_reg, "| %-5s | %-5s | %-6s | %-4s |\n", "IDX", "BMask", "Valid", "BIdx");
}

void print_branch_stack_entry(int i, int bmask, int valid, int bidx) {
    char bmask_str[5], bidx_str[5];
    int_to_binary(bmask, bmask_str, 4);
    int_to_binary(bidx, bidx_str, 4);

    fprintf(bu_reg, "| %-5d | %-5s | %-6d | %-4s |\n", i, bmask_str, valid, bidx_str);
}
/*
void print_reg_header() {
    fprintf(reg, "| %-3s | %-5s |\n", "IDX", "Data");
}
void print_reg_entry(int i, int data) {
    fprintf(reg, "| %-3d | %-5d |\n", i, data);
}
void print_issue_reg_header() {
    fprintf(reg, "| %-3s | %-5s |\n", "IDX", "Data");
}
void print_issue_reg_entry(int i, int data) {
    fprintf(reg, "| %-3d | %-5d |\n", i, data);
}
void print_cdb_header() {
    fprintf(reg, "| %-3s | %-5s |\n", "IDX", "Data");
}
void print_cdb_entry(int i, int data) {
    fprintf(reg, "| %-3d | %-5d |\n", i, data);
}
/*
int main() {
    open_rob_output_file("rob_reg.txt", "rs_reg.txt", "fl_reg.txt", "mt_reg.txt", "bu_reg.txt");

    // Print headers
    print_rob_header();
    print_rs_header();
    print_free_list_header();
    print_map_table_header();
    print_branch_unit_header();

    // Print entries
    print_rob_entry(0, 1, 10, 5, 100, 0, 1, 1, 0);
    print_rs_entry(0, ENTRY_DISPATCHED, FU_ALU, 10, 1, 20, 0, 30);
    print_free_list_entry(0, 1);
    print_map_table_entry(0, 10);
    print_branch_unit_entry(0, 15, 1, 3);

    print_rob_entry(0, 1, 10, 5, 100, 0, 1, 1, 0);
    print_rs_entry(0, ENTRY_DISPATCHED, FU_ALU, 10, 1, 20, 0, 30);
    print_free_list_entry(0, 1);
    print_map_table_entry(0, 10);
    print_branch_unit_entry(0, 15, 1, 3);
    close_output_file();

    printf("Test data has been written to the output files.\n");
    return 0;
}
*/