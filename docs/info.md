<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The Environmental Mapping Processor is a small digital ASIC designed to process environmental measurements for field monitoring and geospatial data-collection applications.

The design supports three independent environmental measurement channels:

- Temperature
- Relative humidity
- Atmospheric pressure

An external environmental sensor provides digitized measurements to the system. Each measurement is represented as an unsigned 8-bit value and supplied to the ASIC through `uio_in[7:0]`.

The measurement type is selected using `ui_in[1:0]`:

| `ui_in[1:0]` | Measurement |
|---|---|
| `00` | Temperature |
| `01` | Humidity |
| `10` | Pressure |
| `11` | Reserved |

When `ui_in[2]` (`sample_valid`) is asserted for a clock cycle, the ASIC captures the value on `uio_in[7:0]` and updates the statistics for the selected environmental channel.

Each channel independently maintains:

- Latest measurement
- Minimum observed measurement
- Maximum observed measurement
- Eight-sample average

The average is calculated in hardware using an accumulator. Eight consecutive measurements of the same type are summed, and the resulting value is divided by eight using a three-bit right shift. This avoids the area cost of implementing a general-purpose hardware divider and is suitable for the limited area of a single Tiny Tapeout tile.

The desired processed result is selected with `ui_in[4:3]`:

| `ui_in[4:3]` | Output |
|---|---|
| `00` | Latest measurement |
| `01` | Eight-sample average |
| `10` | Minimum measurement |
| `11` | Maximum measurement |

The selected 8-bit result is continuously presented on `uo_out[7:0]`.

`ui_in[5]` clears the accumulated statistics, minimums, maximums, sample counters, and calculated averages.

The design is intended to act as a low-area environmental data-processing core. A future field-deployed system could associate the processed environmental observations with geographic locations to produce datasets for GIS analysis and environmental mapping.

## How to test

Set `ena` high to enable the design.

Reset the ASIC by driving `rst_n` low for at least two clock cycles and then driving `rst_n` high.

### Submit a measurement

1. Select the environmental measurement type using `ui_in[1:0]`:

   - `00` = Temperature
   - `01` = Humidity
   - `10` = Pressure

2. Place an unsigned 8-bit measurement value on `uio_in[7:0]`.

3. Drive `ui_in[2]` (`sample_valid`) high.

4. Allow one rising edge of `clk` to occur.

5. Drive `ui_in[2]` low before submitting the next measurement.

The ASIC will store the measurement and update the statistics for the selected channel.

### Read a result

Keep the desired measurement type selected with `ui_in[1:0]`.

Select the result using `ui_in[4:3]`:

- `00` = Latest measurement
- `01` = Eight-sample average
- `10` = Minimum measurement
- `11` = Maximum measurement

Read the resulting value from `uo_out[7:0]`.

For example, submitting the following eight temperature samples:

`64, 66, 68, 70, 72, 74, 76, 78`

should produce:

- Latest = `78`
- Minimum = `64`
- Maximum = `78`
- Eight-sample average = `71`

Temperature, humidity, and pressure statistics are maintained independently, so measurements may be submitted to the three channels without overwriting the state of the other channels.

To clear the accumulated statistics, drive `ui_in[5]` high for one clock cycle.

The Cocotb test suite in `test/test.py` automatically verifies:

- Latest-value tracking
- Minimum-value tracking
- Maximum-value tracking
- Eight-sample averaging
- Independent temperature, humidity, and pressure channels
- Statistics reset behavior

The RTL tests can be run using the Tiny Tapeout test environment:

    cd test
    make

The GitHub Actions workflows additionally run the Tiny Tapeout test, lint, synthesis, physical-design, and precheck flows.

## External hardware

The ASIC processes already digitized environmental measurements and therefore requires an external sensor to obtain real-world environmental data.

The intended sensor is a **BME280 environmental sensor breakout**, which provides:

- Temperature
- Relative humidity
- Atmospheric pressure

The BME280 supports digital communication using I2C or SPI.

For the initial Tiny Tapeout implementation, the BME280 is not connected directly to an I2C controller inside the ASIC. Instead, the Tiny Tapeout demo board microcontroller can communicate with the BME280, convert the sensor measurements into the compact 8-bit representation expected by the ASIC, and present those measurements to `uio_in[7:0]`.

This keeps the ASIC focused on environmental data processing while minimizing logic utilization within the single Tiny Tapeout tile.

Required hardware for a physical demonstration:

- Tiny Tapeout ASIC
- Tiny Tapeout demo board
- BME280 temperature/humidity/pressure sensor breakout
- Jumper wires for connecting the sensor to the demo board

No analog sensor interface is required inside the ASIC because the BME280 performs the environmental sensing and analog-to-digital conversion internally.
