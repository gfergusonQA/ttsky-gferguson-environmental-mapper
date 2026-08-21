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
     * ui_in[1:0] = sensor type
     *   00 temperature
     *   01 humidity
     *   10 pressure
     *
     * ui_in[2] = sample_valid / write strobe
     *
     * ui_in[4:3] = normal output selector
     *   00 latest
     *   01 8-sample average
     *   10 minimum
     *   11 maximum
     *
     * ui_in[5] = clear statistics
     *
     * ui_in[7:6] = operating mode
     *   00 normal
     *   01 program low threshold
     *   10 program high threshold
     *   11 anomaly/status output
     *
     * uio_in[7:0] = sensor value or threshold value
     * uo_out[7:0] = selected result/status
     */

    wire [1:0] sensor_type;
    wire       sample_valid;
    wire [1:0] output_select;
    wire       clear_stats;
    wire [1:0] mode;

    assign sensor_type   = ui_in[1:0];
    assign sample_valid  = ui_in[2];
    assign output_select = ui_in[4:3];
    assign clear_stats   = ui_in[5];
    assign mode          = ui_in[7:6];


    // ------------------------------------------------------------
    // Datapath
    // ------------------------------------------------------------

    wire [10:0] sensor_value_ext;

    assign sensor_value_ext = {
        3'b000,
        uio_in
    };


    // ------------------------------------------------------------
    // Temperature state
    // ------------------------------------------------------------

    reg [7:0] temp_latest;
    reg [7:0] temp_min;
    reg [7:0] temp_max;
    reg [7:0] temp_average;

    reg [10:0] temp_sum;
    reg [3:0]  temp_count;

    wire [10:0] temp_next_sum;

    assign temp_next_sum =
        temp_sum + sensor_value_ext;


    // ------------------------------------------------------------
    // Humidity state
    // ------------------------------------------------------------

    reg [7:0] humidity_latest;
    reg [7:0] humidity_min;
    reg [7:0] humidity_max;
    reg [7:0] humidity_average;

    reg [10:0] humidity_sum;
    reg [3:0]  humidity_count;

    wire [10:0] humidity_next_sum;

    assign humidity_next_sum =
        humidity_sum + sensor_value_ext;


    // ------------------------------------------------------------
    // Pressure state
    // ------------------------------------------------------------

    reg [7:0] pressure_latest;
    reg [7:0] pressure_min;
    reg [7:0] pressure_max;
    reg [7:0] pressure_average;

    reg [10:0] pressure_sum;
    reg [3:0]  pressure_count;

    wire [10:0] pressure_next_sum;

    assign pressure_next_sum =
        pressure_sum + sensor_value_ext;


    // ------------------------------------------------------------
    // Programmable thresholds
    // ------------------------------------------------------------

    reg [7:0] temp_low_threshold;
    reg [7:0] temp_high_threshold;

    reg [7:0] humidity_low_threshold;
    reg [7:0] humidity_high_threshold;

    reg [7:0] pressure_low_threshold;
    reg [7:0] pressure_high_threshold;


    // ------------------------------------------------------------
    // Sequential processing
    // ------------------------------------------------------------

    always @(posedge clk)
    begin
        if (!rst_n)
        begin
            temp_latest  <= 8'd0;
            temp_min     <= 8'hFF;
            temp_max     <= 8'd0;
            temp_average <= 8'd0;
            temp_sum     <= 11'd0;
            temp_count   <= 4'd0;

            humidity_latest  <= 8'd0;
            humidity_min     <= 8'hFF;
            humidity_max     <= 8'd0;
            humidity_average <= 8'd0;
            humidity_sum     <= 11'd0;
            humidity_count   <= 4'd0;

            pressure_latest  <= 8'd0;
            pressure_min     <= 8'hFF;
            pressure_max     <= 8'd0;
            pressure_average <= 8'd0;
            pressure_sum     <= 11'd0;
            pressure_count   <= 4'd0;

            temp_low_threshold      <= 8'd0;
            temp_high_threshold     <= 8'hFF;

            humidity_low_threshold  <= 8'd0;
            humidity_high_threshold <= 8'hFF;

            pressure_low_threshold  <= 8'd0;
            pressure_high_threshold <= 8'hFF;
        end

        else if (ena)
        begin

            // ----------------------------------------------------
            // Clear accumulated statistics
            // Thresholds are intentionally preserved.
            // ----------------------------------------------------

            if (clear_stats)
            begin
                temp_min     <= 8'hFF;
                temp_max     <= 8'd0;
                temp_average <= 8'd0;
                temp_sum     <= 11'd0;
                temp_count   <= 4'd0;

                humidity_min     <= 8'hFF;
                humidity_max     <= 8'd0;
                humidity_average <= 8'd0;
                humidity_sum     <= 11'd0;
                humidity_count   <= 4'd0;

                pressure_min     <= 8'hFF;
                pressure_max     <= 8'd0;
                pressure_average <= 8'd0;
                pressure_sum     <= 11'd0;
                pressure_count   <= 4'd0;
            end

            // ----------------------------------------------------
            // Program LOW threshold
            // ----------------------------------------------------

            else if ((mode == 2'b01) && sample_valid)
            begin
                case (sensor_type)

                    2'b00:
                        temp_low_threshold <= uio_in;

                    2'b01:
                        humidity_low_threshold <= uio_in;

                    2'b10:
                        pressure_low_threshold <= uio_in;

                    default:
                    begin
                    end

                endcase
            end

            // ----------------------------------------------------
            // Program HIGH threshold
            // ----------------------------------------------------

            else if ((mode == 2'b10) && sample_valid)
            begin
                case (sensor_type)

                    2'b00:
                        temp_high_threshold <= uio_in;

                    2'b01:
                        humidity_high_threshold <= uio_in;

                    2'b10:
                        pressure_high_threshold <= uio_in;

                    default:
                    begin
                    end

                endcase
            end

            // ----------------------------------------------------
            // Normal sample processing
            // ----------------------------------------------------

            else if ((mode == 2'b00) && sample_valid)
            begin
                case (sensor_type)

                    // Temperature
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
                                temp_next_sum[10:3];

                            temp_sum   <= 11'd0;
                            temp_count <= 4'd0;
                        end
                        else
                        begin
                            temp_sum   <= temp_next_sum;
                            temp_count <= temp_count + 1'b1;
                        end
                    end


                    // Humidity
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
                                humidity_next_sum[10:3];

                            humidity_sum   <= 11'd0;
                            humidity_count <= 4'd0;
                        end
                        else
                        begin
                            humidity_sum   <= humidity_next_sum;
                            humidity_count <= humidity_count + 1'b1;
                        end
                    end


                    // Pressure
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
                                pressure_next_sum[10:3];

                            pressure_sum   <= 11'd0;
                            pressure_count <= 4'd0;
                        end
                        else
                        begin
                            pressure_sum   <= pressure_next_sum;
                            pressure_count <= pressure_count + 1'b1;
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
    // Threshold / anomaly detection
    // ------------------------------------------------------------

    wire temp_low_event;
    wire temp_high_event;

    wire humidity_low_event;
    wire humidity_high_event;

    wire pressure_low_event;
    wire pressure_high_event;

    wire any_anomaly;


    assign temp_low_event =
        temp_latest < temp_low_threshold;

    assign temp_high_event =
        temp_latest > temp_high_threshold;


    assign humidity_low_event =
        humidity_latest < humidity_low_threshold;

    assign humidity_high_event =
        humidity_latest > humidity_high_threshold;


    assign pressure_low_event =
        pressure_latest < pressure_low_threshold;

    assign pressure_high_event =
        pressure_latest > pressure_high_threshold;


    assign any_anomaly =
        temp_low_event      |
        temp_high_event     |
        humidity_low_event  |
        humidity_high_event |
        pressure_low_event  |
        pressure_high_event;


    // ------------------------------------------------------------
    // Status byte
    //
    // bit 7 = any anomaly
    // bit 6 = temperature high
    // bit 5 = temperature low
    // bit 4 = humidity high
    // bit 3 = humidity low
    // bit 2 = pressure high
    // bit 1 = pressure low
    // bit 0 = reserved
    // ------------------------------------------------------------

    wire [7:0] status;

    assign status = {
        any_anomaly,
        temp_high_event,
        temp_low_event,
        humidity_high_event,
        humidity_low_event,
        pressure_high_event,
        pressure_low_event,
        1'b0
    };


    // ------------------------------------------------------------
    // Normal result multiplexer
    // ------------------------------------------------------------

    reg [7:0] normal_result;

    always @(*)
    begin
        normal_result = 8'd0;

        case (sensor_type)

            2'b00:
            begin
                case (output_select)
                    2'b00: normal_result = temp_latest;
                    2'b01: normal_result = temp_average;
                    2'b10: normal_result = temp_min;
                    2'b11: normal_result = temp_max;
                endcase
            end


            2'b01:
            begin
                case (output_select)
                    2'b00: normal_result = humidity_latest;
                    2'b01: normal_result = humidity_average;
                    2'b10: normal_result = humidity_min;
                    2'b11: normal_result = humidity_max;
                endcase
            end


            2'b10:
            begin
                case (output_select)
                    2'b00: normal_result = pressure_latest;
                    2'b01: normal_result = pressure_average;
                    2'b10: normal_result = pressure_min;
                    2'b11: normal_result = pressure_max;
                endcase
            end


            default:
                normal_result = 8'd0;

        endcase
    end


    // ------------------------------------------------------------
    // Output
    // ------------------------------------------------------------

    assign uo_out =
        (mode == 2'b11)
        ? status
        : normal_result;


    // uio pins are inputs only.
    assign uio_out = 8'd0;
    assign uio_oe  = 8'd0;

endmodule
