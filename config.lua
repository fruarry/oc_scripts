return {
    global_config = {
        addr_buffer = "56ccaa62-33bb-48b7-8468-11ad98e118b7",
        addr_buffer_inv = "92032b5f-0de2-423d-b637-b93083313824",
        side_buffer = sides.bottom,
    
        buffer_off_level = 0.9,
        buffer_on_level = 0.1,
    
        error_retry_interval = 5,
    
        status_interval = 1,
        watchdog_interval = 0.2,
    },
    reactor_config = {
        [1] = {
            pattern_name = "quad_uranium",
    
            addr_rsio = "185e3c6b-b187-4b69-9e53-e05e12ffdaa0",
            addr_transposer = "30cd614d-b6af-4ccb-b8a4-685f67ae6c66",
            addr_reactor_chamber = "263b1c80-115a-440e-b490-8a0538a58387",
    
            side_reactor = sides.north,
            side_input = sides.west,
            side_output = sides.east,
            side_rsio = sides.west,
            color_on = colors.green,
            color_error = colors.orange,
            color_start_en = colors.white,
            color_stop_en = colors.red,
            allow_auto_start = true
        },
        [2] = {
            pattern_name = "glowstone",
    
            addr_rsio = "185e3c6b-b187-4b69-9e53-e05e12ffdaa0",
            addr_transposer = "532c3e2a-2841-4a16-8ba9-fbd8109eaa72",
            addr_reactor_chamber = "8a1823fe-5693-4917-ba97-bf184da9b2c3",
    
            side_reactor = sides.north,
            side_input = sides.west,
            side_output = sides.east,
            side_rsio = sides.west,
            color_on = colors.lime,
            color_error = colors.yellow,
            color_start_en = colors.gray,
            color_stop_en = colors.pink,
            allow_auto_start = false
        }
    }
}