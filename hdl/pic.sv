`ifdef LINTING
`include "types.sv"
`endif

import types::*;

module v35_edge_trigger(
    input clk,
    input ce,
    input reset,

    input signal,
    input dir,
    output reg trigger
);

reg prev_signal;
always_ff @(posedge clk) begin
    if (reset) begin
        trigger <= 0;
        prev_signal <= signal;
    end else if (ce) begin
        trigger <= (signal ^ prev_signal) & (prev_signal ^ dir);
        prev_signal <= signal;
    end
end

endmodule


module v35_pic(
    input clk,
    input ce,
    input reset,
    
    input NMI,
    input INT,
    input [7:0] EXIC0,
    input [7:0] EXIC1,
    input [7:0] EXIC2,

    output reg [7:0] ISPR,

    input IE,

    output reg NMI_clear,
    output reg INT_clear,
    output reg EXIC0_clear,
    output reg EXIC1_clear,
    output reg EXIC2_clear,


    output int_req,
    output reg [7:0] int_vector,
    input int_ack,

    input fint
);

function bit [7:0] prio_mask(bit [2:0] prio);
    case(prio)
        3'd0: return 8'b00000001;
        3'd1: return 8'b00000011;
        3'd2: return 8'b00000111;
        3'd3: return 8'b00001111;
        3'd4: return 8'b00011111;
        3'd5: return 8'b00111111;
        3'd6: return 8'b01111111;
        3'd7: return 8'b11111111;
    endcase
endfunction

enum
{
    IRQ_NONE,
    IRQ_NMI,
    IRQ_INT,
    IRQ_EXIC0,
    IRQ_EXIC1,
    IRQ_EXIC2
} irq_type;

assign int_req = irq_type != IRQ_NONE;

reg ack_prev;
reg second_ack;

always_ff @(posedge clk) begin
    NMI_clear <= 0;
    INT_clear <= 0;
    EXIC0_clear <= 0;
    EXIC1_clear <= 0;
    EXIC2_clear <= 0;

    if (reset) begin
        ISPR <= 0;
        irq_type <= IRQ_NONE;
        second_ack <= 0;
    end else if (ce) begin
        ack_prev <= int_ack;
        
        if (fint) begin
            if (ISPR[0]) ISPR[0] <= 0;
            else if (ISPR[1]) ISPR[1] <= 0;
            else if (ISPR[2]) ISPR[2] <= 0;
            else if (ISPR[3]) ISPR[3] <= 0;
            else if (ISPR[4]) ISPR[4] <= 0;
            else if (ISPR[5]) ISPR[5] <= 0;
            else if (ISPR[6]) ISPR[6] <= 0;
            else if (ISPR[7]) ISPR[7] <= 0;
        end

        if (int_req) begin
            if (int_ack & ~ack_prev) begin
                second_ack <= 1;
                if (~second_ack) begin
                    case(irq_type)
                        IRQ_NMI: begin
                            NMI_clear <= 1;
                            int_vector <= 8'd2;
                        end
                        IRQ_INT: begin
                            INT_clear <= 1;
                            int_vector <= 8'd0; // TODO: read from external
                        end
                        IRQ_EXIC0: begin
                            EXIC0_clear <= 1;
                            int_vector <= 8'd24;
                            ISPR <= ISPR | ( 8'd1 << EXIC0[2:0] );
                        end
                        IRQ_EXIC1: begin
                            EXIC1_clear <= 1;
                            int_vector <= 8'd25;
                            ISPR <= ISPR | ( 8'd1 << EXIC0[2:0] );
                        end
                        IRQ_EXIC2: begin
                            EXIC2_clear <= 1;
                            int_vector <= 8'd26;
                            ISPR <= ISPR | ( 8'd1 << EXIC0[2:0] );
                        end
                        default: begin end // How?
                    endcase
                end else begin
                    second_ack <= 0;
                    irq_type <= IRQ_NONE;
                end
            end
        end else begin
            second_ack <= 0;
            if (NMI) begin
                irq_type <= IRQ_NMI;
            end else if (INT & IE) begin
                irq_type <= IRQ_INT;
            end else if (IE) begin
                if ((ISPR & prio_mask(EXIC0[2:0])) == 8'd0) begin
                    if (EXIC0[7] & ~EXIC0[6]) begin
                        irq_type <= IRQ_EXIC0;
                    end else if (EXIC1[7] & ~EXIC1[6]) begin
                        irq_type <= IRQ_EXIC1;
                    end else if (EXIC2[7] & ~EXIC2[6]) begin
                        irq_type <= IRQ_EXIC2;
                    end
                end
            end
        end
    end
end


endmodule