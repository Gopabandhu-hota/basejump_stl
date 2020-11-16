module testbench();
 
  `include "bsg_noc_links.vh"

  import bsg_noc_pkg::*;

  // Sync with trace gen
  localparam hdr_width_p = 32;
  localparam cord_width_p = 5;
  localparam len_width_p = 3;
  localparam flit_width_p = 8;
  localparam pr_data_width_p = 16;
  localparam wh_hdr_width_p = cord_width_p + len_width_p;
  localparam pr_hdr_width_p = hdr_width_p - wh_hdr_width_p;
  localparam hdr_flits_p = hdr_width_p / flit_width_p;
  localparam data_width_p = flit_width_p*(2**len_width_p-hdr_flits_p+1);
  localparam data_flits_p = data_width_p / flit_width_p;

  localparam ring_width_p = 1+`BSG_MAX(`BSG_MAX(hdr_width_p, pr_data_width_p), flit_width_p);
  localparam rom_data_width_p = 4 + ring_width_p;
  localparam rom_addr_width_p = 32;

  logic clk;
  bsg_nonsynth_clock_gen #(
    .cycle_time_p(1000)
  ) clock_gen (
    .o(clk)
  );

  logic reset;
  bsg_nonsynth_reset_gen #(
    .num_clocks_p(1)
    ,.reset_cycles_lo_p(4)
    ,.reset_cycles_hi_p(4)
  ) reset_gen (
    .clk_i(clk)
    ,.async_reset_o(reset)
  );

  `declare_bsg_ready_and_link_sif_s(flit_width_p, bsg_ready_and_link_sif_s);
  bsg_ready_and_link_sif_s link_lo, link_li;

  bsg_ready_and_link_sif_s out_link_lo, out_link_li;

  `declare_bsg_ready_and_link_sif_s(flit_width_p/4, bsg_narrow_link_sif_s);
  bsg_narrow_link_sif_s narrow_link_li, narrow_link_lo;

  logic [3:0] backpressure_cnt;
  always_ff @(posedge clk)
    if (reset)
      backpressure_cnt <= '0;
    else
      backpressure_cnt <= backpressure_cnt + 1'b1;

  wire backpressure = backpressure_cnt[0]; //^{backpressure_cnt[1], backpressure_cnt[0]};
  //wire backpressure = '0;

  bsg_parallel_in_serial_out_passthrough
   #(.width_p(flit_width_p/4), .els_p(4))
   pisop
    (.clk_i(clk)
     ,.reset_i(reset)

     ,.data_i(link_li.data)
     ,.v_i(link_li.v)
     ,.ready_and_o(link_lo.ready_and_rev)

     ,.data_o(narrow_link_lo.data)
     ,.v_o(narrow_link_lo.v)
     ,.ready_and_i(narrow_link_li.ready_and_rev & ~backpressure)
     );

  bsg_serial_in_parallel_out_passthrough
   #(.width_p(flit_width_p/4), .els_p(4))
   sipop
    (.clk_i(clk)
     ,.reset_i(reset)

     ,.data_i(narrow_link_lo.data)
     ,.v_i(narrow_link_lo.v & ~backpressure)
     ,.ready_and_o(narrow_link_li.ready_and_rev)

     ,.data_o(out_link_li.data)
     ,.v_o(out_link_li.v)
     ,.ready_and_i(out_link_lo.ready_and_rev)
     );
  // TODO: Actually set
  assign out_link_lo.ready_and_rev = 1'b1;

  logic [63:0] counter;
  always_ff @(posedge clk)
    if (reset)
      counter <= '0;
    else
      counter <= counter + 1'b1;
  wire select_left  = counter[0] ^ counter[1];
  wire select_right = ~select_left;

  logic [flit_width_p-1:0] left_data_li;
  logic left_yumi_lo;
  wire left_v_li = select_left;
  initial
    begin
      left_data_li = '0;

      for (integer i = 0; i < 100; i+=0)
        begin
          left_data_li = i << (cord_width_p);

          @(left_yumi_lo);
          @(negedge clk);
          i += 1'b1;
        end
    end

  logic [flit_width_p-1:0] right_data_li;
  logic right_yumi_lo;
  wire right_v_li = select_right;
  initial
    begin
      right_data_li = '0;

      for (integer i = 0; i < 100; i+=0)
        begin
          right_data_li = i << (cord_width_p);

          @(right_yumi_lo);
          @(negedge clk);
          i += 1'b1;
        end
    end

  logic [S:P][flit_width_p-1:0] data_li, data_lo;
  logic [S:P]                   v_li, v_lo;
  logic [S:P]                   yumi_lo, ready_li;
  bsg_mesh_router
   #(.width_p(flit_width_p)
     ,.x_cord_width_p(1)
     ,.y_cord_width_p(cord_width_p-1)
     ,.dirs_lp(5)
     )
   router
    (.clk_i(clk)
     ,.reset_i(reset)

     ,.data_i(data_li)
     ,.v_i(v_li)
     ,.yumi_o(yumi_lo)

     ,.data_o(data_lo)
     ,.v_o(v_lo)
     ,.ready_i(ready_li)

     ,.my_x_i('0)
     ,.my_y_i('0)
     );
  assign data_li[S:N] = '0;
  assign data_li[E] = right_data_li;
  assign data_li[W] = left_data_li;
  assign data_li[P] = '0;

  assign v_li[S:N] = '0;
  assign v_li[E] = right_v_li;
  assign v_li[W] = left_v_li;
  assign v_li[P] = '0;

  assign right_yumi_lo = yumi_lo[E];
  assign left_yumi_lo  = yumi_lo[W];

  assign ready_li[S:N] = '0;
  assign ready_li[E] = '0;
  assign ready_li[W] = '0;
  assign ready_li[P] = link_lo.ready_and_rev;

  assign link_li.data = data_lo[P];
  assign link_li.v    = v_lo[P];

  initial 
    begin
      $assertoff();
      @(posedge clk)
      @(negedge reset)
      $asserton();
    end

endmodule
