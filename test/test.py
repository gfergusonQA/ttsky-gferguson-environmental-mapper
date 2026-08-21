import cocotb

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.triggers import Timer


SENSOR_TEMP = 0b00
SENSOR_HUMIDITY = 0b01
SENSOR_PRESSURE = 0b10


OUTPUT_LATEST = 0b00
OUTPUT_AVERAGE = 0b01
OUTPUT_MIN = 0b10
OUTPUT_MAX = 0b11


def control_word(
    sensor_type,
    sample_valid=0,
    output_select=0,
    clear_stats=0
):
    value = sensor_type

    value |= sample_valid << 2
    value |= output_select << 3
    value |= clear_stats << 5

    return value


async def reset_dut(dut):

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    dut.rst_n.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.rst_n.value = 1

    await RisingEdge(dut.clk)


async def send_sample(
    dut,
    sensor_type,
    value
):

    dut.uio_in.value = value

    dut.ui_in.value = control_word(
        sensor_type,
        sample_valid=1
    )

    await RisingEdge(dut.clk)

    dut.ui_in.value = control_word(
        sensor_type,
        sample_valid=0
    )

    await RisingEdge(dut.clk)


async def read_result(
    dut,
    sensor_type,
    output_select
):

    dut.ui_in.value = control_word(
        sensor_type,
        output_select=output_select
    )

    await Timer(1, unit="ns")

    return int(dut.uo_out.value)


@cocotb.test()
async def test_temperature_latest_min_max(dut):

    cocotb.start_soon(
        Clock(
            dut.clk,
            10,
            unit="ns"
        ).start()
    )

    await reset_dut(dut)


    values = [
        68,
        70,
        72,
        69,
        75
    ]


    for value in values:

        await send_sample(
            dut,
            SENSOR_TEMP,
            value
        )


    latest = await read_result(
        dut,
        SENSOR_TEMP,
        OUTPUT_LATEST
    )

    minimum = await read_result(
        dut,
        SENSOR_TEMP,
        OUTPUT_MIN
    )

    maximum = await read_result(
        dut,
        SENSOR_TEMP,
        OUTPUT_MAX
    )


    assert latest == 75
    assert minimum == 68
    assert maximum == 75


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


    values = [
        64,
        66,
        68,
        70,
        72,
        74,
        76,
        78
    ]


    for value in values:

        await send_sample(
            dut,
            SENSOR_TEMP,
            value
        )


    average = await read_result(
        dut,
        SENSOR_TEMP,
        OUTPUT_AVERAGE
    )


    expected = sum(values) // 8

    assert average == expected


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
        72
    )

    await send_sample(
        dut,
        SENSOR_HUMIDITY,
        45
    )

    await send_sample(
        dut,
        SENSOR_PRESSURE,
        101
    )


    temp = await read_result(
        dut,
        SENSOR_TEMP,
        OUTPUT_LATEST
    )

    humidity = await read_result(
        dut,
        SENSOR_HUMIDITY,
        OUTPUT_LATEST
    )

    pressure = await read_result(
        dut,
        SENSOR_PRESSURE,
        OUTPUT_LATEST
    )


    assert temp == 72
    assert humidity == 45
    assert pressure == 101


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


    await send_sample(
        dut,
        SENSOR_TEMP,
        50
    )

    await send_sample(
        dut,
        SENSOR_TEMP,
        100
    )


    dut.ui_in.value = control_word(
        SENSOR_TEMP,
        clear_stats=1
    )

    await RisingEdge(dut.clk)


    dut.ui_in.value = 0

    await RisingEdge(dut.clk)


    await send_sample(
        dut,
        SENSOR_TEMP,
        70
    )


    minimum = await read_result(
        dut,
        SENSOR_TEMP,
        OUTPUT_MIN
    )

    maximum = await read_result(
        dut,
        SENSOR_TEMP,
        OUTPUT_MAX
    )


    assert minimum == 70
    assert maximum == 70


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
    # Program temperature LOW threshold = 50
    #
    # mode = 01 -> ui_in[7:6]
    # sensor_type = 00 -> temperature
    # sample_valid = 1 -> ui_in[2]
    # --------------------------------------------------------

    dut.uio_in.value = 50

    dut.ui_in.value = (
        (0b01 << 6) |
        (1 << 2) |
        SENSOR_TEMP
    )

    await RisingEdge(dut.clk)

    dut.ui_in.value = 0

    await RisingEdge(dut.clk)


    # --------------------------------------------------------
    # Program temperature HIGH threshold = 100
    #
    # mode = 10
    # --------------------------------------------------------

    dut.uio_in.value = 100

    dut.ui_in.value = (
        (0b10 << 6) |
        (1 << 2) |
        SENSOR_TEMP
    )

    await RisingEdge(dut.clk)

    dut.ui_in.value = 0

    await RisingEdge(dut.clk)


    # --------------------------------------------------------
    # Send normal temperature = 75
    #
    # mode = 00
    # --------------------------------------------------------

    await send_sample(
        dut,
        SENSOR_TEMP,
        75
    )


    # Read status
    # mode = 11

    dut.ui_in.value = (
        (0b11 << 6) |
        SENSOR_TEMP
    )

    await Timer(1, unit="ns")

    status = int(dut.uo_out.value)

    assert status == 0


    # --------------------------------------------------------
    # Send HIGH temperature = 110
    # --------------------------------------------------------

    dut.ui_in.value = 0

    await send_sample(
        dut,
        SENSOR_TEMP,
        110
    )

    dut.ui_in.value = (
        (0b11 << 6) |
        SENSOR_TEMP
    )

    await Timer(1, unit="ns")

    status = int(dut.uo_out.value)

    # bit 7 = any anomaly
    # bit 6 = temperature high

    assert status & (1 << 7)
    assert status & (1 << 6)

    # low flag should NOT be set
    assert not (status & (1 << 5))


    # --------------------------------------------------------
    # Send LOW temperature = 40
    # --------------------------------------------------------

    dut.ui_in.value = 0

    await send_sample(
        dut,
        SENSOR_TEMP,
        40
    )

    dut.ui_in.value = (
        (0b11 << 6) |
        SENSOR_TEMP
    )

    await Timer(1, unit="ns")

    status = int(dut.uo_out.value)

    # bit 7 = any anomaly
    # bit 5 = temperature low

    assert status & (1 << 7)
    assert status & (1 << 5)

    # high flag should NOT be set
    assert not (status & (1 << 6))
