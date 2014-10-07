module test_bsg_data_gen #(parameter   channel_width_p ="inv"
                           , parameter num_channels_p  = -1
                           )
   (input clk_i
    , input reset_i
    , input yumi_i
    , output [channel_width_p*num_channels_p-1:0] o
    );

   logic [channel_width_p-1:0] data_r;

   always @(posedge clk_i)
     if (reset_i)
       data_r <= 0;
     else
       if (yumi_i)
         data_r <= data_r + 1;

   wire [channel_width_p*num_channels_p-1:0] send_data;

   localparam lg_ring_bytes_lp = $clog2(num_channels_p);

   wire [$max(lg_ring_bytes_lp-1,0):0]       ring_bytes
                                       = $max(lg_ring_bytes_lp,1) ' (num_channels_p);

   genvar                              i;

   if (num_channels_p > 1)
     for (i = 0; i < num_channels_p; i++)
       begin
          wire [lg_ring_bytes_lp-1:0] my_id = i[lg_ring_bytes_lp-1:0];

	  if (lg_ring_bytes_lp < channel_width_p)
            assign send_data[i*channel_width_p+:channel_width_p]
              = { my_id, data_r[0+:channel_width_p-lg_ring_bytes_lp]};
	  else
	    assign send_data[i*channel_width_p+:channel_width_p]
	      = { data_r[0+:channel_width_p]};
       end
   else
     assign send_data[0+:channel_width_p] = data_r;

   assign o = send_data;

endmodule // test_bsg_data_gen
