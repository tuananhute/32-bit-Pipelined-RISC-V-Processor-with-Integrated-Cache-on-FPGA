create_clock -name cpu_clk \
    -period 20.000 \
    -waveform {0.000 10.000} \
    [get_ports clk]