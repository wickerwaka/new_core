`ifdef LINTING
`include "types.sv"
`endif

import types::*;

// V35 bus control with prefetch
module bus_control_unit_v35(
    input               clk,
    input               ce_1,
    input               ce_2,


    // Pins
    input               reset,
    input               ready,

    output  reg         r_w,
    output  reg         n_ube,
    output  reg         n_mreq,
    output  reg         n_iostb,
    output  reg         n_mstb,

    output  reg [19:0]  addr,
    output      [15:0]  dout,
    input       [15:0]  din,


    // Execution Unit Communication
    input       [15:0]  reg_ps,

    // instruction queue
    // inputs only read on ce1
    input               pfp_set,
    input               block_prefetch,
    input       [15:0]  ipq_head,
    output  reg [7:0]   ipq[8],
    output      [3:0]   ipq_len,

    // Data pointer read/write
    input       [19:0]  dp_addr,
    input       [15:0]  dp_dout,
    output      [15:0]  dp_din,
    input               dp_write,
    input               dp_wide,
    input               dp_io,
    input               dp_req,
    output              dp_ready,

    output  reg         implementation_fault,

    // Interrupt handling
    input               intreq,
    output  reg         intack,
    output              intack_cycle,
    output  reg  [7:0]  intvec
);

bcu_t_state_e t_state;
bcu_cycle_type_e cycle_type;

assign intack_cycle = cycle_type == INT_ACK1 | cycle_type == INT_ACK2;

reg dp_busy;
reg dp_final_cycle;
reg dp_req2;
reg [15:0] dp_din_buf;
reg [15:0] reg_pfp;
reg discard_ipq_fetch = 0;
assign ipq_len = pfp_set ? 4'd0 : reg_pfp[3:0] - ipq_head[3:0];

wire dp_bus_ready = (dp_final_cycle && ce_1 && t_state == T_3 && ready);
assign dp_ready = ~dp_req & ~dp_req2 & (dp_bus_ready | ~dp_busy);
int intack_idles;

reg [3:0] prefetch_delay;

always_comb begin
    if (~dp_addr[0]) dp_din = din;
    else if (dp_addr[0] & dp_wide) dp_din = { din[7:0], dp_din_buf[15:8] };
    else dp_din = { din[7:0], din[15:8] };
end

always_ff @(posedge clk) begin
    if (reset) begin
        t_state <= T_IDLE;

        n_ube <= 0;
        n_mreq <= 1;
        n_mstb <= 1;
        n_iostb <= 1;

        cycle_type <= IPQ_FETCH;
        intack <= 0;

        implementation_fault <= 0;

        reg_pfp <= ipq_head;
        discard_ipq_fetch <= 0;

        dp_req2 <= 0;
        dp_busy <= 0;
        dp_din_buf <= 16'hffff;

        prefetch_delay <= 4'd0;

    end else if (ce_1 | ce_2) begin
        bit [15:0] cur_pfp;
        cur_pfp = reg_pfp;
        if (pfp_set) begin
            reg_pfp <= ipq_head;
            cur_pfp = ipq_head;
            discard_ipq_fetch <= 1;
        end

        if (dp_req) dp_req2 <= 1;

        if (~intreq) intack <= 0;

        if (ce_1 && t_state == T_1) begin
            n_mreq <= 0;
        end else if (ce_1 && t_state == T_2) begin
            if (cycle_type == IO_READ || cycle_type == IO_WRITE)
                n_iostb <= 0;
            else
                n_mstb <= 0;
            dout <= dp_addr[0] ? { dp_dout[7:0], dp_dout[15:8] } : dp_dout;
        end else if (ce_2 && t_state == T_IDLE) begin
            bit do_prefetch;

            n_mreq <= 1;
            n_mstb <= 1;
            n_iostb <= 1;

            intack_idles <= intack_idles + 1;
            
            do_prefetch = 0;

            if (block_prefetch) begin
                do_prefetch = 0;
                prefetch_delay <= 4'd2;
            end else if (ipq_len < 5) begin
                prefetch_delay <= 4'd1;
                if (prefetch_delay > 4'd0) do_prefetch = 1;
                do_prefetch = 1;
            end else begin
                prefetch_delay <= 4'd0;
            end

            if (cycle_type == INT_ACK1) begin
                if (intack_idles == 6) begin
                    t_state <= T_1;
                    cycle_type <= INT_ACK2;
                    intack_idles <= 0;
                end
            end else if (cycle_type == INT_ACK2) begin
                if (intack_idles == 5) begin
                    cycle_type <= IPQ_FETCH;
                    intack <= 1;
                end
            end else if (dp_busy) begin // Second byte of an unaligned access
                t_state <= T_1;
                addr <= addr + 20'd1; // V35: full 20-bit address is incremented
                n_ube <= 1;
                dp_final_cycle <= 1;
            end else if (intreq & ~intack) begin
                cycle_type <= INT_ACK1;
                t_state <= T_1;
                intack_idles <= 0;
                n_ube <= 1;
            end else if (dp_req | dp_req2) begin
                dp_req2 <= 0;
                t_state <= T_1;
                r_w <= ~dp_write;
                n_mreq <= 0;
                addr <= dp_addr;
                if (dp_io) begin
                    cycle_type <= dp_write ? IO_WRITE : IO_READ;
                end else begin
                    cycle_type <= dp_write ? MEM_WRITE : MEM_READ;
                end

                n_ube <= (~dp_wide & ~dp_addr[0]);
                dp_final_cycle <= ~dp_wide | ~dp_addr[0];
                dp_busy <= 1;
            end else if (do_prefetch) begin
                t_state <= T_1;
                r_w <= 1;
                n_mreq <= 0;
                cycle_type <= IPQ_FETCH;
                addr <= {reg_ps, 4'd0} + {4'd0, cur_pfp};
                n_ube <= 0; // always
                discard_ipq_fetch <= 0;
                //prefetch_delay <= 4'd0;
            end
        end else if (ce_2 && t_state == T_1) begin
            t_state <= T_2;
        end else if (ce_2 && t_state == T_2) begin
            t_state <= T_3;
        end else if (ce_1 && t_state == T_3) begin
            if (ready) begin
                dp_final_cycle <= 1;
                case(cycle_type)
                    IPQ_FETCH: begin
                        if (~pfp_set & ~discard_ipq_fetch) begin
                            if (reg_pfp[0]) begin
                                ipq[reg_pfp[2:0]] <= din[15:8];
                                reg_pfp <= reg_pfp + 16'd1;
                            end else begin
                                ipq[reg_pfp[2:0]] <= din[7:0];
                                ipq[reg_pfp[2:0] + 1] <= din[15:8];
                                reg_pfp <= reg_pfp + 16'd2;
                            end
                        end
                    end
                    MEM_READ, IO_READ: begin
                        dp_din_buf <= din;
                        dp_busy <= ~dp_final_cycle;
                    end
                    MEM_WRITE, IO_WRITE: begin
                        dp_busy <= ~dp_final_cycle;
                    end
                    INT_ACK1,
                    INT_ACK2: begin
                        intvec <= din[7:0];
                    end
                    default: begin end
                endcase

                t_state <= T_IDLE;
            end
        end
    end
end

endmodule