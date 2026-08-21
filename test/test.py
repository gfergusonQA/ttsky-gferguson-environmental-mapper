import cocotb

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.triggers import Timer


# ------------------------------------------------------------
# Sensor / data types
# ------------------------------------------------------------

SENSOR_TEMP = 0b00
SENSOR_HUMIDITY = 0b01
SENSOR_PRESSURE = 0b10
SENSOR_SPATIAL = 0b11


# ------------------------------------------------------------
# Operating modes
#
# ui_in[7:6]
# ------------------------------------------------------------

MODE_NORMAL = 0b00
MODE_LOW_TARGET = 0b01
MODE_HIGH_RADIUS = 0b10
MODE_STATUS = 0b11


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

async def reset_dut(dut):

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.rst_n.value = 1

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")


async def send_sample(
    dut,
    sensor_type,
    value
):

    """
    Submit one environmental sample.

    mode = 00
    sample_valid = 1
    sensor_type = requested environmental channel
    """

    dut.uio_in.value = value

    dut.ui_in.value = (
        (MODE_NORMAL << 6) |
        (1 << 2) |
        sensor_type
    )

    await RisingEdge(dut.clk)

    # Remove sample_valid while keeping the selected sensor.
    dut.ui_in.value = sensor_type

    await Timer(1, unit="ns")


async def read_latest(
    dut,
    sensor_type
):

    """
    ui_in[3] = 0 -> latest
    """

    dut.ui_in.value = sensor_type

    await Timer(1, unit="ns")

    return int(dut.uo_out.value)


async def read_average(
    dut,
    sensor_type
):

    """
    ui_in[3] = 1 -> 8-sample average
    """

    dut.ui_in.value = (
        (1 << 3) |
        sensor_type
    )

    await Timer(1, unit="ns")

    return int(dut.uo_out.value)


async def program_low_threshold(
    dut,
    sensor_type,
    value
):

    dut.uio_in.value = value

    dut.ui_in.value = (
        (MODE_LOW_TARGET << 6) |
        (1 << 2) |
        sensor_type
    )

    await RisingEdge(dut.clk)

    dut.ui_in.value = 0

    await RisingEdge(dut.clk)


async def program_high_threshold(
    dut,
    sensor_type,
    value
):

    dut.uio_in.value = value

    dut.ui_in.value = (
        (MODE_HIGH_RADIUS << 6) |
        (1 << 2) |
        sensor_type
    )

    await RisingEdge(dut.clk)

    dut.ui_in.value = 0

    await RisingEdge(dut.clk)


async def read_status(dut):

    """
    Status byte:

    bit 7 = location-aware environmental event
    bit 6 = any environmental anomaly
    bit 5 = inside target spatial zone
    bit 4 = temperature high
    bit 3 = temperature low
    bit 2 = humidity high
    bit 1 = humidity low
    bit 0 = pressure anomaly
    """

    dut.ui_in.value = (
        MODE_STATUS << 6
    )

    await Timer(1, unit="ns")

    return int(dut.uo_out.value)


async def program_target(
    dut,
    x,
    y
):

    """
    Spatial target:

    mode = 01
    sensor_type = 11

    uio_in[5:3] = X
    uio_in[2:0] = Y
    """

    value = (
        ((x & 0x7) << 3) |
        (y & 0x7)
    )

    dut.uio_in.value = value

    dut.ui_in.value = (
        (MODE_LOW_TARGET << 6) |
        (1 << 2) |
        SENSOR_SPATIAL
    )

    await RisingEdge(dut.clk)

    dut.ui_in.value = 0

    await RisingEdge(dut.clk)


async def program_radius(
    dut,
    radius
):

    """
    Spatial radius:

    mode = 10
    sensor_type = 11

    uio_in[3:0] = radius
    """

    dut.uio_in.value = radius & 0xF

    dut.ui_in.value = (
        (MODE_HIGH_RADIUS << 6) |
        (1 << 2) |
        SENSOR_SPATIAL
    )

    await RisingEdge(dut.clk)

    dut.ui_in.value = 0

    await RisingEdge(dut.clk)


async def set_current_location(
    dut,
    x,
    y
):

    """
    Current spatial location:

    mode = 00
    sensor_type = 11

    uio_in[5:3] = X
    uio_in[2:0] = Y
    """

    value = (
        ((x & 0x7) << 3) |
        (y & 0x7)
    )

    dut.uio_in.value = value

    dut.ui_in.value = (
        (MODE_NORMAL << 6) |
        (1 << 2) |
        SENSOR_SPATIAL
    )

    await RisingEdge(dut.clk)

    # Keep spatial channel selected, but remove write strobe.
    dut.ui_in.value = SENSOR_SPATIAL

    await Timer(1, unit="ns")


async def read_distance(dut):

    """
    Selecting sensor_type = 11 in normal mode returns
    Manhattan distance on uo_out[3:0].
    """

    dut.ui_in.value = SENSOR_SPATIAL

    await Timer(1, unit="ns")

    return int(dut.uo_out.value)


# ------------------------------------------------------------
# Test 1
#
# Latest environmental values
# ------------------------------------------------------------

@cocotb.test()
async def test_environmental_latest_values(dut):

    cocotb.start_soon(
        Clock(
            dut.clk,
            10,
            unit="ns"
        ).start()
    )

    await reset_dut(dut)

    await send_sample(
        dut,
        SENSOR_TEMP,
        72
    )

    assert await read_latest(
        dut,
        SENSOR_TEMP
    ) == 72


    await send_sample(
        dut,
        SENSOR_HUMIDITY,
        48
    )

    assert await read_latest(
        dut,
        SENSOR_HUMIDITY
    ) == 48


    await send_sample(
        dut,
        SENSOR_PRESSURE,
        101
    )

    assert await read_latest(
        dut,
        SENSOR_PRESSURE
    ) == 101


# ------------------------------------------------------------
# Test 2
#
# Eight-sample average
# ------------------------------------------------------------

@cocotb.test()
async def test_temperature_average(dut):

    cocotb.start_soon(
        Clock(
            dut.clk,
            10,
            unit="ns"
        ).start()
    )

    await reset_dut(dut)

    samples = [
        64,
        66,
        68,
        70,
        72,
        74,
        76,
        78
    ]

    for sample in samples:

        await send_sample(
            dut,
            SENSOR_TEMP,
            sample
        )

    expected_average = sum(samples) // 8

    assert expected_average == 71

    result = await read_average(
        dut,
        SENSOR_TEMP
    )

    assert result == expected_average


# ------------------------------------------------------------
# Test 3
#
# Independent environmental channels
# ------------------------------------------------------------

@cocotb.test()
async def test_independent_sensor_channels(dut):

    cocotb.start_soon(
        Clock(
            dut.clk,
            10,
            unit="ns"
        ).start()
    )

    await reset_dut(dut)

    await send_sample(
        dut,
        SENSOR_TEMP,
        75
    )

    await send_sample(
        dut,
        SENSOR_HUMIDITY,
        51
    )

    await send_sample(
        dut,
        SENSOR_PRESSURE,
        103
    )

    assert await read_latest(
        dut,
        SENSOR_TEMP
    ) == 75

    assert await read_latest(
        dut,
        SENSOR_HUMIDITY
    ) == 51

    assert await read_latest(
        dut,
        SENSOR_PRESSURE
    ) == 103


# ------------------------------------------------------------
# Test 4
#
# Clear accumulated average state
# ------------------------------------------------------------

@cocotb.test()
async def test_clear_statistics(dut):

    cocotb.start_soon(
        Clock(
            dut.clk,
            10,
            unit="ns"
        ).start()
    )

    await reset_dut(dut)

    samples = [
        40,
        48,
        56,
        64,
        72,
        80,
        88,
        96
    ]

    for sample in samples:

        await send_sample(
            dut,
            SENSOR_TEMP,
            sample
        )

    result = await read_average(
        dut,
        SENSOR_TEMP
    )

    assert result == 68


    # --------------------------------------------------------
    # Clear statistics
    #
    # ui_in[5] = 1
    # --------------------------------------------------------

    dut.ui_in.value = (
        1 << 5
    )

    await RisingEdge(dut.clk)

    dut.ui_in.value = 0

    await RisingEdge(dut.clk)


    result = await read_average(
        dut,
        SENSOR_TEMP
    )

    assert result == 0


# ------------------------------------------------------------
# Test 5
#
# Environmental programmable thresholds
# ------------------------------------------------------------

@cocotb.test()
async def test_temperature_threshold_anomalies(dut):

    cocotb.start_soon(
        Clock(
            dut.clk,
            10,
            unit="ns"
        ).start()
    )

    await reset_dut(dut)


    # --------------------------------------------------------
    # Temperature thresholds
    #
    # LOW  = 50
    # HIGH = 100
    # --------------------------------------------------------

    await program_low_threshold(
        dut,
        SENSOR_TEMP,
        50
    )

    await program_high_threshold(
        dut,
        SENSOR_TEMP,
        100
    )


    # --------------------------------------------------------
    # Normal temperature
    # --------------------------------------------------------

    await send_sample(
        dut,
        SENSOR_TEMP,
        75
    )

    status = await read_status(dut)

    assert status == 0


    # --------------------------------------------------------
    # Temperature above high threshold
    #
    # bit 6 = any anomaly
    # bit 4 = temperature high
    # --------------------------------------------------------

    await send_sample(
        dut,
        SENSOR_TEMP,
        110
    )

    status = await read_status(dut)

    assert status & (1 << 6)
    assert status & (1 << 4)

    assert not (
        status & (1 << 3)
    )


    # --------------------------------------------------------
    # Temperature below low threshold
    #
    # bit 6 = any anomaly
    # bit 3 = temperature low
    # --------------------------------------------------------

    await send_sample(
        dut,
        SENSOR_TEMP,
        40
    )

    status = await read_status(dut)

    assert status & (1 << 6)
    assert status & (1 << 3)

    assert not (
        status & (1 << 4)
    )


# ------------------------------------------------------------
# Test 6
#
# Spatial Manhattan distance and radius
# ------------------------------------------------------------

@cocotb.test()
async def test_spatial_distance_and_zone(dut):

    cocotb.start_soon(
        Clock(
            dut.clk,
            10,
            unit="ns"
        ).start()
    )

    await reset_dut(dut)


    # --------------------------------------------------------
    # Target location = (3, 4)
    # Radius = 3
    # --------------------------------------------------------

    await program_target(
        dut,
        3,
        4
    )

    await program_radius(
        dut,
        3
    )


    # --------------------------------------------------------
    # Current location = (4, 5)
    #
    # Manhattan distance:
    #
    # |4 - 3| + |5 - 4|
    #
    # 1 + 1 = 2
    #
    # 2 <= 3 -> inside target zone
    # --------------------------------------------------------

    await set_current_location(
        dut,
        4,
        5
    )

    distance = await read_distance(dut)

    assert distance == 2


    status = await read_status(dut)

    # bit 5 = inside target zone
    assert status & (1 << 5)


    # --------------------------------------------------------
    # Move outside the target radius.
    #
    # Current location = (7, 7)
    #
    # |7 - 3| + |7 - 4|
    #
    # 4 + 3 = 7
    #
    # 7 > 3 -> outside
    # --------------------------------------------------------

    await set_current_location(
        dut,
        7,
        7
    )

    distance = await read_distance(dut)

    assert distance == 7


    status = await read_status(dut)

    assert not (
        status & (1 << 5)
    )


# ------------------------------------------------------------
# Test 7
#
# Combined environmental + spatial event
# ------------------------------------------------------------

@cocotb.test()
async def test_location_aware_environmental_event(dut):

    cocotb.start_soon(
        Clock(
            dut.clk,
            10,
            unit="ns"
        ).start()
    )

    await reset_dut(dut)


    # --------------------------------------------------------
    # Temperature high threshold = 100
    # --------------------------------------------------------

    await program_high_threshold(
        dut,
        SENSOR_TEMP,
        100
    )


    # --------------------------------------------------------
    # Spatial target = (3, 3)
    # Radius = 2
    # --------------------------------------------------------

    await program_target(
        dut,
        3,
        3
    )

    await program_radius(
        dut,
        2
    )


    # --------------------------------------------------------
    # Current position = (4, 3)
    #
    # Distance = 1
    #
    # Therefore inside target zone.
    # --------------------------------------------------------

    await set_current_location(
        dut,
        4,
        3
    )


    # --------------------------------------------------------
    # Send anomalously high temperature.
    # --------------------------------------------------------

    await send_sample(
        dut,
        SENSOR_TEMP,
        120
    )


    status = await read_status(dut)


    # bit 7 = location-aware event
    assert status & (1 << 7)

    # bit 6 = environmental anomaly
    assert status & (1 << 6)

    # bit 5 = inside target zone
    assert status & (1 << 5)

    # bit 4 = temperature high
    assert status & (1 << 4)


    # --------------------------------------------------------
    # Move outside the target zone.
    #
    # Environmental anomaly remains, but the combined
    # location-aware event must disappear.
    # --------------------------------------------------------

    await set_current_location(
        dut,
        7,
        7
    )

    status = await read_status(dut)


    # Environmental anomaly still exists.
    assert status & (1 << 6)

    # No longer inside target zone.
    assert not (
        status & (1 << 5)
    )

    # Combined location-aware event must be off.
    assert not (
        status & (1 << 7)
    )
