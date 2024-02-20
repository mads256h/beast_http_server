include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(beast_http_server_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(beast_http_server_setup_options)
  option(beast_http_server_ENABLE_HARDENING "Enable hardening" ON)
  option(beast_http_server_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    beast_http_server_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    beast_http_server_ENABLE_HARDENING
    OFF)

  beast_http_server_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR beast_http_server_PACKAGING_MAINTAINER_MODE)
    option(beast_http_server_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(beast_http_server_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(beast_http_server_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(beast_http_server_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(beast_http_server_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(beast_http_server_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(beast_http_server_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(beast_http_server_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(beast_http_server_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(beast_http_server_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(beast_http_server_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(beast_http_server_ENABLE_PCH "Enable precompiled headers" OFF)
    option(beast_http_server_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(beast_http_server_ENABLE_IPO "Enable IPO/LTO" ON)
    option(beast_http_server_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(beast_http_server_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(beast_http_server_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(beast_http_server_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(beast_http_server_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(beast_http_server_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(beast_http_server_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(beast_http_server_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(beast_http_server_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(beast_http_server_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(beast_http_server_ENABLE_PCH "Enable precompiled headers" OFF)
    option(beast_http_server_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      beast_http_server_ENABLE_IPO
      beast_http_server_WARNINGS_AS_ERRORS
      beast_http_server_ENABLE_USER_LINKER
      beast_http_server_ENABLE_SANITIZER_ADDRESS
      beast_http_server_ENABLE_SANITIZER_LEAK
      beast_http_server_ENABLE_SANITIZER_UNDEFINED
      beast_http_server_ENABLE_SANITIZER_THREAD
      beast_http_server_ENABLE_SANITIZER_MEMORY
      beast_http_server_ENABLE_UNITY_BUILD
      beast_http_server_ENABLE_CLANG_TIDY
      beast_http_server_ENABLE_CPPCHECK
      beast_http_server_ENABLE_COVERAGE
      beast_http_server_ENABLE_PCH
      beast_http_server_ENABLE_CACHE)
  endif()

  beast_http_server_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (beast_http_server_ENABLE_SANITIZER_ADDRESS OR beast_http_server_ENABLE_SANITIZER_THREAD OR beast_http_server_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(beast_http_server_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(beast_http_server_global_options)
  if(beast_http_server_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    beast_http_server_enable_ipo()
  endif()

  beast_http_server_supports_sanitizers()

  if(beast_http_server_ENABLE_HARDENING AND beast_http_server_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR beast_http_server_ENABLE_SANITIZER_UNDEFINED
       OR beast_http_server_ENABLE_SANITIZER_ADDRESS
       OR beast_http_server_ENABLE_SANITIZER_THREAD
       OR beast_http_server_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${beast_http_server_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${beast_http_server_ENABLE_SANITIZER_UNDEFINED}")
    beast_http_server_enable_hardening(beast_http_server_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(beast_http_server_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(beast_http_server_warnings INTERFACE)
  add_library(beast_http_server_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  beast_http_server_set_project_warnings(
    beast_http_server_warnings
    ${beast_http_server_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(beast_http_server_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(beast_http_server_options)
  endif()

  include(cmake/Sanitizers.cmake)
  beast_http_server_enable_sanitizers(
    beast_http_server_options
    ${beast_http_server_ENABLE_SANITIZER_ADDRESS}
    ${beast_http_server_ENABLE_SANITIZER_LEAK}
    ${beast_http_server_ENABLE_SANITIZER_UNDEFINED}
    ${beast_http_server_ENABLE_SANITIZER_THREAD}
    ${beast_http_server_ENABLE_SANITIZER_MEMORY})

  set_target_properties(beast_http_server_options PROPERTIES UNITY_BUILD ${beast_http_server_ENABLE_UNITY_BUILD})

  if(beast_http_server_ENABLE_PCH)
    target_precompile_headers(
      beast_http_server_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(beast_http_server_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    beast_http_server_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(beast_http_server_ENABLE_CLANG_TIDY)
    beast_http_server_enable_clang_tidy(beast_http_server_options ${beast_http_server_WARNINGS_AS_ERRORS})
  endif()

  if(beast_http_server_ENABLE_CPPCHECK)
    beast_http_server_enable_cppcheck(${beast_http_server_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(beast_http_server_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    beast_http_server_enable_coverage(beast_http_server_options)
  endif()

  if(beast_http_server_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(beast_http_server_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(beast_http_server_ENABLE_HARDENING AND NOT beast_http_server_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR beast_http_server_ENABLE_SANITIZER_UNDEFINED
       OR beast_http_server_ENABLE_SANITIZER_ADDRESS
       OR beast_http_server_ENABLE_SANITIZER_THREAD
       OR beast_http_server_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    beast_http_server_enable_hardening(beast_http_server_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
