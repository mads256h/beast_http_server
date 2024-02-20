add_executable(http_server main.cpp)

target_link_libraries(
        http_server
        PRIVATE beast_http_server::beast_http_server_options
        beast_http_server::beast_http_server_warnings)

target_link_system_libraries(
        http_server
        PRIVATE
        CLI11::CLI11
        fmt::fmt
        spdlog::spdlog
        Boost::asio
)

target_include_directories(http_server PRIVATE "${CMAKE_BINARY_DIR}/configured_files/include")
