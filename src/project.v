/*
 * Copyright (c) 2026 Gina Ferguson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_gina_env_monitor (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    /*
     * Tiny Environmental Monitoring Processor
     *
     * ui_in:
     *
     * [1:0] sensor type
     *       00 = temperature
     *       01 = humidity
     *       10 = pressure
     *       11 = reserved
     *
     * [2]   sample_valid
     *
     * [4:3] output selector
     *       00 = latest
     *       01 = 8-sample average
     *       10 = minimum
     *       11 = maximum
     *
     * [5]   clear statistics
     *
     * uio_in[7:0]
     *       sensor measurement
     *
     * uo_out[7:0]
     *       selected processed result
     */

    wire [1:0] sensor_type;
    wire       sample_valid;
    wire [1:0] output_select;
    wire       clear_stats;
    wire [10:0] sensor_value_ext;
    wire [10:0] temp_next_sum;
    wire [10:0] humidity_next_sum;
    wire [10:0] pressure_next_sum;
    
    assign temp_next_sum =
        temp_sum + sensor_value_ext;
    
    assign humidity_next_sum =
        humidity_sum + sensor_value_ext;
    
    assign pressure_next_sum =
        pressure_sum + sensor_value_ext;

    assign sensor_value_ext = {
        3'b000,
        uio_in
    };

    assign sensor_type   = ui_in[1:0];
    assign sample_valid  = ui_in[2];
    assign output_select = ui_in[4:3];
    assign clear_stats   = ui_in[5];


    // ------------------------------------------------------------
    // Temperature state
    // ------------------------------------------------------------

    reg [7:0] temp_latest;
    reg [7:0] temp_min;
    reg [7:0] temp_max;

    reg [10:0] temp_sum;
    reg [3:0]  temp_count;

    reg [7:0] temp_average;


    // ------------------------------------------------------------
    // Humidity state
    // ------------------------------------------------------------

    reg [7:0] humidity_latest;
    reg [7:0] humidity_min;
    reg [7:0] humidity_max;

    reg [10:0] humidity_sum;
    reg [3:0]  humidity_count;

    reg [7:0] humidity_average;


    // ------------------------------------------------------------
    // Pressure state
    // ------------------------------------------------------------

    reg [7:0] pressure_latest;
    reg [7:0] pressure_min;
    reg [7:0] pressure_max;

    reg [10:0] pressure_sum;
    reg [3:0]  pressure_count;

    reg [7:0] pressure_average;


    // ------------------------------------------------------------
    // Sample processing
    //
    // Eight samples are accumulated.
    //
    // Average = sum / 8
    //         = sum >> 3
    //
    // This is intentionally cheap in hardware.
    // ------------------------------------------------------------

    always @(posedge clk)
    begin

        if (!rst_n)
        begin

            temp_latest  <= 8'd0;
            temp_min     <= 8'hFF;
            temp_max     <= 8'd0;
            temp_sum     <= 11'd0;
            temp_count   <= 4'd0;
            temp_average <= 8'd0;

            humidity_latest  <= 8'd0;
            humidity_min     <= 8'hFF;
            humidity_max     <= 8'd0;
            humidity_sum     <= 11'd0;
            humidity_count   <= 4'd0;
            humidity_average <= 8'd0;

            pressure_latest  <= 8'd0;
            pressure_min     <= 8'hFF;
            pressure_max     <= 8'd0;
            pressure_sum     <= 11'd0;
            pressure_count   <= 4'd0;
            pressure_average <= 8'd0;

        end

        else if (ena)
        begin

            if (clear_stats)
            begin

                temp_min     <= 8'hFF;
                temp_max     <= 8'd0;
                temp_sum     <= 11'd0;
                temp_count   <= 4'd0;
                temp_average <= 8'd0;

                humidity_min     <= 8'hFF;
                humidity_max     <= 8'd0;
                humidity_sum     <= 11'd0;
                humidity_count   <= 4'd0;
                humidity_average <= 8'd0;

                pressure_min     <= 8'hFF;
                pressure_max     <= 8'd0;
                pressure_sum     <= 11'd0;
                pressure_count   <= 4'd0;
                pressure_average <= 8'd0;

            end

            else if (sample_valid)
            begin

                case (sensor_type)

                    // --------------------------------------------
                    // Temperature
                    // --------------------------------------------

                    2'b00:
                    begin

                        temp_latest <= uio_in;

                        if (uio_in < temp_min)
                            temp_min <= uio_in;

                        if (uio_in > temp_max)
                            temp_max <= uio_in;


                        if (temp_count == 4'd7)
                        begin
                            temp_average <=
                                (temp_sum + sensor_value_ext) >> 3;
                        
                            temp_sum   <= 11'd0;
                            temp_count <= 4'd0;
                        end
                        else
                        begin
                            temp_sum <=
                                temp_sum + sensor_value_ext;
                        
                            temp_count <=
                                temp_count + 1'b1;
                        end
                    end


                    // --------------------------------------------
                    // Humidity
                    // --------------------------------------------

                    2'b01:
                    begin

                        humidity_latest <= uio_in;

                        if (uio_in < humidity_min)
                            humidity_min <= uio_in;

                        if (uio_in > humidity_max)
                            humidity_max <= uio_in;


                        if (humidity_count == 4'd7)
                        begin
                            humidity_average <=
                                (humidity_sum + sensor_value_ext) >> 3;
                        
                            humidity_sum   <= 11'd0;
                            humidity_count <= 4'd0;
                        end
                        else
                        begin
                            humidity_sum <=
                                humidity_sum + sensor_value_ext;
                        
                            humidity_count <=
                                humidity_count + 1'b1;
                        end
                    end


                    // --------------------------------------------
                    // Pressure
                    // --------------------------------------------

                    2'b10:
                    begin

                        pressure_latest <= uio_in;

                        if (uio_in < pressure_min)
                            pressure_min <= uio_in;

                        if (uio_in > pressure_max)
                            pressure_max <= uio_in;


                        if (pressure_count == 4'd7)
                        begin
                            pressure_average <=
                                (pressure_sum + sensor_value_ext) >> 3;
                        
                            pressure_sum   <= 11'd0;
                            pressure_count <= 4'd0;
                        end
                        else
                        begin
                            pressure_sum <=
                                pressure_sum + sensor_value_ext;
                        
                            pressure_count <=
                                pressure_count + 1'b1;
                        end
                    end


                    default:
                    begin
                    end

                endcase

            end

        end

    end


    // ------------------------------------------------------------
    // Result mux
    // ------------------------------------------------------------

    reg [7:0] result;

    always @(*)
    begin

        result = 8'd0;

        case (sensor_type)

            2'b00:
            begin

                case (output_select)

                    2'b00:
                        result = temp_latest;

                    2'b01:
                        result = temp_average;

                    2'b10:
                        result = temp_min;

                    2'b11:
                        result = temp_max;

                endcase

            end


            2'b01:
            begin

                case (output_select)

                    2'b00:
                        result = humidity_latest;

                    2'b01:
                        result = humidity_average;

                    2'b10:
                        result = humidity_min;

                    2'b11:
                        result = humidity_max;

                endcase

            end


            2'b10:
            begin

                case (output_select)

                    2'b00:
                        result = pressure_latest;

                    2'b01:
                        result = pressure_average;

                    2'b10:
                        result = pressure_min;

                    2'b11:
                        result = pressure_max;

                endcase

            end


            default:
                result = 8'd0;

        endcase

    end


    assign uo_out = result;


    // uio pins operate as inputs only.
    assign uio_out = 8'd0;
    assign uio_oe  = 8'd0;


    // Suppress unused input warning.
    wire _unused;

    assign _unused = &{
        1'b0,
        ui_in[7:6]
    };

endmodule
