`ifdef LINTING
`include "types.sv"
`endif

import types::*;

module pre_decode(
    input clk,
    input ce,

    input [3:0] q_len,
    input [7:0] q0,
    input [7:0] q1,
    input [7:0] q2,

    output reg valid_op,

    output pre_decode_t decoded
);

wire [23:0] q = { q0, q1, q2 };

/* verilator lint_off CASEX */

always_ff @(posedge clk) begin
    pre_decode_t d;
    if (ce) begin
        valid_op <= 0;

        casex(q)
        `include "opcodes.svh"
        endcase

        if (q_len < d.pre_size) valid_op <= 0;
        
        decoded <= d;
    end
end

endmodule