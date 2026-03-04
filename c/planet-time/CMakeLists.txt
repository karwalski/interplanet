cmake_minimum_required(VERSION 3.14)
project(interplanet VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Warnings ──────────────────────────────────────────────────────────────────
add_compile_options(
  $<$<COMPILE_LANGUAGE:C>:-Wall>
  $<$<COMPILE_LANGUAGE:C>:-Wextra>
  $<$<COMPILE_LANGUAGE:C>:-Wpedantic>
)

# ── Source ────────────────────────────────────────────────────────────────────
set(LIB_SRC src/libinterplanet.c)
set(LIB_INC include)

# ── Shared library ────────────────────────────────────────────────────────────
add_library(interplanet_shared SHARED ${LIB_SRC})
target_include_directories(interplanet_shared PUBLIC ${LIB_INC})
target_link_libraries(interplanet_shared m)
set_target_properties(interplanet_shared PROPERTIES
  OUTPUT_NAME interplanet
  PUBLIC_HEADER include/libinterplanet.h
)

# ── Static library ────────────────────────────────────────────────────────────
add_library(interplanet_static STATIC ${LIB_SRC})
target_include_directories(interplanet_static PUBLIC ${LIB_INC})
target_link_libraries(interplanet_static m)
set_target_properties(interplanet_static PROPERTIES OUTPUT_NAME interplanet_s)

# ── C test binary ─────────────────────────────────────────────────────────────
add_executable(test_libinterplanet tests/test_libinterplanet.c)
target_include_directories(test_libinterplanet PRIVATE ${LIB_INC})
target_link_libraries(test_libinterplanet interplanet_static m)

# ── CTest integration ─────────────────────────────────────────────────────────
enable_testing()
add_test(NAME unit_tests COMMAND test_libinterplanet)

# ── Install ───────────────────────────────────────────────────────────────────
install(TARGETS interplanet_shared interplanet_static
        LIBRARY DESTINATION lib
        ARCHIVE DESTINATION lib
        PUBLIC_HEADER DESTINATION include)
