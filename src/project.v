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
     * Environmental + Spatial Edge Processor
     *
     * ui_in[1:0] = data type
     *
     *   00 = temperature
     *   01 = humidity
     *   10 = pressure
     *   11 = spatial
     *
     * ui_in[2] = sample_valid / write strobe
     *
     * ui_in[4:3] = environmental result selector
     *
     *   00 = latest
     *   01 = 8-sample average
     *   10 = minimum
     *   11 = maximum
     *
     * ui_in[5] = clear environmental statistics
     *
     * ui_in[7:6] = operating mode
     *
     *   00 = normal sample / program current location
     *   01 = program LOW threshold / spatial target
     *   10 = program HIGH threshold / spatial radius
     *   11 = combined status
     *
     * Environmental uio_in:
     *   [7:0] = unsigned measurement
     *
     * Spatial coordinates:
     *   [5:3] = X (0-7)
     *   [2:0] = Y (0-7)
     *
     * Spatial radius:
     *   [3:0] = radius (0-14)
     *
     * Spatial engine:
     *
     *   distance =
     *       |current_x - target_x|
     *       +
     *       |current_y - target_y|
     *
     *   inside_target_zone =
     *       distance <= target_radius
     */


    // ------------------------------------------------------------
    // Input decoding
    // ------------------------------------------------------------

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
    // Environmental datapath
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
    // Programmable environmental thresholds
    // ------------------------------------------------------------

    reg [7:0] temp_low_threshold;
    reg [7:0] temp_high_threshold;

    reg [7:0] humidity_low_threshold;
    reg [7:0] humidity_high_threshold;

    reg [7:0] pressure_low_threshold;
    reg [7:0] pressure_high_threshold;


    // ------------------------------------------------------------
    // Compact spatial engine
    //
    // 3-bit X and Y produce an 8 x 8 local spatial grid.
    //
    // This keeps the spatial calculation on the ASIC while
    // reducing area compared with the earlier 4-bit implementation.
    // ------------------------------------------------------------

    reg [2:0] current_x;
    reg [2:0] current_y;

    reg [2:0] target_x;
    reg [2:0] target_y;

    reg [3:0] target_radius;


    wire [2:0] x_distance;
    wire [2:0] y_distance;

    wire [3:0] manhattan_distance;
    wire       inside_target_zone;


    assign x_distance =
        (current_x >= target_x)
        ? (current_x - target_x)
        : (target_x - current_x);


    assign y_distance =
        (current_y >= target_y)
        ? (current_y - target_y)
        : (target_y - current_y);


    assign manhattan_distance =
        {1'b0, x_distance} +
        {1'b0, y_distance};


    assign inside_target_zone =
        manhattan_distance <= target_radius;


    // ------------------------------------------------------------
    // Sequential processing
    // ------------------------------------------------------------

    always @(posedge clk)
    begin

        if (!rst_n)
        begin

            // Temperature
            temp_latest  <= 8'd0;
            temp_min     <= 8'hFF;
            temp_max     <= 8'd0;
            temp_average <= 8'd0;
            temp_sum     <= 11'd0;
            temp_count   <= 4'd0;

            // Humidity
            humidity_latest  <= 8'd0;
            humidity_min     <= 8'hFF;
            humidity_max     <= 8'd0;
            humidity_average <= 8'd0;
            humidity_sum     <= 11'd0;
            humidity_count   <= 4'd0;

            // Pressure
            pressure_latest  <= 8'd0;
            pressure_min     <= 8'hFF;
            pressure_max     <= 8'd0;
            pressure_average <= 8'd0;
            pressure_sum     <= 11'd0;
            pressure_count   <= 4'd0;

            // Thresholds
            temp_low_threshold      <= 8'd0;
            temp_high_threshold     <= 8'hFF;

            humidity_low_threshold  <= 8'd0;
            humidity_high_threshold <= 8'hFF;

            pressure_low_threshold  <= 8'd0;
            pressure_high_threshold <= 8'hFF;

            // Spatial configuration
            current_x     <= 3'd0;
            current_y     <= 3'd0;

            target_x      <= 3'd0;
            target_y      <= 3'd0;

            target_radius <= 4'd0;

        end

        else if (ena)
        begin

            // ----------------------------------------------------
            // Clear environmental statistics.
            //
            // Thresholds and spatial configuration are retained.
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
            // MODE 01
            //
            // Environmental:
            //   program LOW threshold
            //
            // Spatial:
            //   program target X/Y
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

                    2'b11:
                    begin
                        target_x <= uio_in[5:3];
                        target_y <= uio_in[2:0];
                    end

                endcase

            end


            // ----------------------------------------------------
            // MODE 10
            //
            // Environmental:
            //   program HIGH threshold
            //
            // Spatial:
            //   program target radius
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

                    2'b11:
                        target_radius <= uio_in[3:0];

                endcase

            end


            // ----------------------------------------------------
            // MODE 00
            //
            // Normal environmental samples or current location.
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

                            temp_sum <= temp_next_sum;

                            temp_count <=
                                temp_count + 1'b1;

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

                            humidity_sum <=
                                humidity_next_sum;

                            humidity_count <=
                                humidity_count + 1'b1;

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

                            pressure_sum <=
                                pressure_next_sum;

                            pressure_count <=
                                pressure_count + 1'b1;

                        end

                    end


                    // Current spatial position
                    2'b11:
                    begin

                        current_x <= uio_in[5:3];
                        current_y <= uio_in[2:0];

                    end

                endcase

            end

        end

    end


    // ------------------------------------------------------------
    // Environmental anomaly engine
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
    // Combined spatial + environmental event
    // ------------------------------------------------------------

    wire location_aware_event;

    assign location_aware_event =
        any_anomaly &&
        inside_target_zone;


    // ------------------------------------------------------------
    // Status byte
    //
    // bit 7 = location-aware environmental event
    // bit 6 = environmental anomaly
    // bit 5 = inside target zone
    // bit 4 = temperature high
    // bit 3 = temperature low
    // bit 2 = humidity high
    // bit 1 = humidity low
    // bit 0 = pressure anomaly
    // ------------------------------------------------------------

    wire [7:0] status;

    assign status = {
        location_aware_event,
        any_anomaly,
        inside_target_zone,
        temp_high_event,
        temp_low_event,
        humidity_high_event,
        humidity_low_event,
        pressure_high_event | pressure_low_event
    };


    // ------------------------------------------------------------
    // Environmental result multiplexer
    //
    // We intentionally do NOT provide separate target/radius
    // readback paths. The external controller already knows the
    // configuration values it programmed.
    //
    // When sensor_type == spatial and mode != status,
    // the ASIC outputs the calculated Manhattan distance.
    // ------------------------------------------------------------

    reg [7:0] normal_result;

    always @(*)
    begin

        normal_result = 8'd0;

        case (sensor_type)

            // Temperature
            2'b00:
            begin

                case (output_select)

                    2'b00:
                        normal_result = temp_latest;

                    2'b01:
                        normal_result = temp_average;

                    2'b10:
                        normal_result = temp_min;

                    2'b11:
                        normal_result = temp_max;

                endcase

            end


            // Humidity
            2'b01:
            begin

                case (output_select)

                    2'b00:
                        normal_result = humidity_latest;

                    2'b01:
                        normal_result = humidity_average;

                    2'b10:
                        normal_result = humidity_min;

                    2'b11:
                        normal_result = humidity_max;

                endcase

            end


            // Pressure
            2'b10:
            begin

                case (output_select)

                    2'b00:
                        normal_result = pressure_latest;

                    2'b01:
                        normal_result = pressure_average;

                    2'b10:
                        normal_result = pressure_min;

                    2'b11:
                        normal_result = pressure_max;

                endcase

            end


            // Spatial
            //
            // Only expose the calculated distance.
            //
            // Zone/event information is available in status mode.
            2'b11:
            begin

                normal_result = {
                    4'b0000,
                    manhattan_distance
                };

            end

        endcase

    end


    // ------------------------------------------------------------
    // Output
    // ------------------------------------------------------------

    assign uo_out =
        (mode == 2'b11)
        ? status
        : normal_result;


    // ------------------------------------------------------------
    // uio pins are input-only in this design.
    // ------------------------------------------------------------

    assign uio_out = 8'd0;
    assign uio_oe  = 8'd0;

endmodule
