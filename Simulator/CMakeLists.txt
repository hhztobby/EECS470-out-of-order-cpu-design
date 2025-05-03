set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# add all .cpp under the current directory as source
# Get all .cpp files in the current directory
file(GLOB SOURCES "*.c" "*.cpp")

# Add executable or library
add_executable(Simulator ${SOURCES})